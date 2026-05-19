import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/transaction.dart';
import '../../core/constants/app_constants.dart';
import '../../core/logging/app_log.dart';

final transactionsProvider = StateNotifierProvider<TransactionsNotifier, AsyncValue<List<Transaction>>>((ref) {
  return TransactionsNotifier();
});

class TransactionsNotifier extends StateNotifier<AsyncValue<List<Transaction>>> {
  TransactionsNotifier() : super(const AsyncValue.loading()) {
    _init();
  }

  final _supabase = Supabase.instance.client;
  RealtimeChannel? _subscription;

  Future<void> _init() async {
    await fetchTransactions();
    _setupRealtime();
  }

  Future<void> fetchTransactions() async {
    try {
      state = const AsyncValue.loading();
      
      final data = await _supabase
          .from('transactions')
          .select()
          .order('created_at', ascending: false)
          .limit(100);
      
      final transactions = (data as List).map((json) => _mapToTransaction(json)).toList();
      state = AsyncValue.data(transactions);
    } catch (e, st) {
      AppLog.d('Error fetching transactions: $e');
      state = AsyncValue.error(e, st);
    }
  }

  void _setupRealtime() {
    _subscription = _supabase
        .channel('public:transactions')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'transactions',
          callback: (payload) {
            AppLog.d('Real-time transaction change: ${payload.eventType}');
            fetchTransactions();
          },
        )
        .subscribe();
  }

  Transaction _mapToTransaction(Map<String, dynamic> json) {
    return Transaction(
      id: json['id']?.toString() ?? '',
      productId: json['product_id']?.toString() ?? '',
      workerId: json['user_id']?.toString() ?? '',
      productName: json['product_name'] ?? 'Unknown Product',
      productCode: json['product_code'] ?? json['code'] ?? '',
      workerName: json['worker_name'] ?? 'Unknown Worker',
      cartons: (json['cartons'] as num?)?.toInt(),
      pcsPerCarton: (json['pcs_per_carton'] as num?)?.toInt(),
      colorName: json['color_name'],
      warehouseId: json['warehouse_id']?.toString(),
      warehouseName: json['warehouse_name'],
      type: TransactionType.fromString(json['type'] ?? 'OUT'),
      quantity: json['quantity'] ?? 0,
      notes: json['notes'],
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()).toLocal(),
    );
  }

  @override
  void dispose() {
    _subscription?.unsubscribe();
    super.dispose();
  }
}
