import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../domain/entities/transaction.dart';
import '../../core/constants/app_constants.dart';
import '../../core/logging/app_log.dart';
import '../../core/services/server_api_client.dart';
import '../../core/utils/connection_messages.dart';
import 'api_client_provider.dart';

final transactionsProvider =
    StateNotifierProvider<TransactionsNotifier, AsyncValue<List<Transaction>>>(
        (ref) {
  return TransactionsNotifier(ref.watch(apiClientProvider));
});

final productTransactionsProvider =
    FutureProvider.family<List<Transaction>, String>((ref, productId) async {
  final client = ref.watch(apiClientProvider);
  final json =
      await client.get('/transactions?product_id=$productId&limit=1000&page=1');
  final rows = (json is Map ? json['data'] : null) as List? ?? const [];

  DateTime parseDate(dynamic value) {
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toLocal();
    }
    return DateTime.now();
  }

  int? toInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  final transactions = rows.map((entry) {
    final row = Map<String, dynamic>.from(entry as Map);
    return Transaction(
      id: row['id']?.toString() ?? '',
      productId: row['product_id']?.toString() ?? '',
      workerId:
          row['worker_id']?.toString() ?? row['user_id']?.toString() ?? '',
      productName: row['product_name']?.toString() ?? '',
      productCode:
          row['product_code']?.toString() ?? row['code']?.toString() ?? '',
      workerName: row['worker_name']?.toString() ?? '',
      cartons: toInt(row['cartons']),
      pcsPerCarton: toInt(row['pcs_per_carton']),
      colorName: row['color_name']?.toString(),
      warehouseId: row['warehouse_id']?.toString(),
      warehouseName: row['warehouse_name']?.toString(),
      type: TransactionType.fromString(row['type']?.toString() ?? 'OUT'),
      quantity: toInt(row['quantity']) ?? 0,
      notes: row['notes']?.toString(),
      createdAt: parseDate(row['created_at']),
    );
  }).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  return transactions;
});

class TransactionsNotifier
    extends StateNotifier<AsyncValue<List<Transaction>>> {
  TransactionsNotifier([this._client]) : super(const AsyncValue.loading()) {
    _init();
  }

  final ServerApiClient? _client;

  static const _cacheKey = 'cache_transactions_v1';

  Future<void> _init() async {
    // Show last-known data instantly, then revalidate in the background so a
    // cold-starting server doesn't block the screen.
    final hadCache = _loadFromCache();
    await _fetchTransactions(silent: hadCache);
  }

  Future<void> fetchTransactions() => _fetchTransactions();

  /// Populates state from the on-device cache. Returns true if cached data
  /// was found and applied.
  bool _loadFromCache() {
    try {
      final box = Hive.box(AppConstants.settingsBox);
      final cached = box.get(_cacheKey) as String?;
      if (cached == null || cached.isEmpty) return false;
      final decoded = jsonDecode(cached);
      if (decoded is! List) return false;
      final transactions = decoded
          .whereType<Map>()
          .map((row) => _mapToTransaction(Map<String, dynamic>.from(row)))
          .toList();
      if (transactions.isEmpty) return false;
      state = AsyncValue.data(transactions);
      return true;
    } catch (e) {
      AppLog.d('Error loading cached transactions: $e');
      return false;
    }
  }

  void _saveToCache(List<dynamic> rows) {
    try {
      Hive.box(AppConstants.settingsBox).put(_cacheKey, jsonEncode(rows));
    } catch (e) {
      AppLog.d('Error caching transactions: $e');
    }
  }

  Future<void> _fetchTransactions({bool silent = false}) async {
    try {
      if (!silent) state = const AsyncValue.loading();

      final client = _client;
      if (client == null) {
        throw ServerApiException(connectionWarningMessage, 0);
      }

      final json = await client.get('/transactions?limit=5000&page=1');
      final rows = (json is Map ? json['data'] : null) as List? ?? const [];
      final transactions = rows
          .whereType<Map>()
          .map((row) => _mapToTransaction(Map<String, dynamic>.from(row)))
          .toList();
      state = AsyncValue.data(transactions);
      _saveToCache(rows);
    } catch (e, st) {
      AppLog.d('Error fetching transactions: $e');
      // Keep showing cached/last-known data on a background failure.
      if (!silent && !state.hasValue) {
        state = AsyncValue.error(e, st);
      }
    }
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
      createdAt:
          DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String())
              .toLocal(),
    );
  }
}
