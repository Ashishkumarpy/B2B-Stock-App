import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/product.dart';
import '../../core/constants/app_constants.dart';
import '../../core/logging/app_log.dart';

final productsProvider = StateNotifierProvider<ProductsNotifier, AsyncValue<List<Product>>>((ref) {
  return ProductsNotifier();
});

class ProductsNotifier extends StateNotifier<AsyncValue<List<Product>>> {
  ProductsNotifier() : super(const AsyncValue.loading()) {
    _init();
  }

  final _supabase = Supabase.instance.client;
  RealtimeChannel? _subscription;

  Future<void> _init() async {
    await fetchProducts();
    _setupRealtime();
  }

  Future<void> fetchProducts() async {
    try {
      state = const AsyncValue.loading();
      
      final data = await _supabase
          .from('products')
          .select()
          .order('name', ascending: true);
      
      final products = (data as List).map((json) => _mapToProduct(json)).toList();
      state = AsyncValue.data(products);
    } catch (e, st) {
      AppLog.d('Error fetching products: $e');
      state = AsyncValue.error(e, st);
    }
  }

  void _setupRealtime() {
    _subscription = _supabase
        .channel('public:products')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'products',
          callback: (payload) {
            AppLog.d('Real-time product change: ${payload.eventType}');
            fetchProducts(); // Refresh on any change
          },
        )
        .subscribe();
  }

  Product _mapToProduct(Map<String, dynamic> json) {
    // Mapping from Supabase Snake Case to Dart Camel Case
    final imagesList = (json['images'] as List?)?.map((i) => ProductImage.fromMap(i as Map<String, dynamic>)).toList() ?? [];
    
    final colorStocks = <ProductColorStock>[];
    dynamic rawColorStocks = json['color_stocks'];

    if (rawColorStocks is String && rawColorStocks.isNotEmpty) {
      try {
        rawColorStocks = jsonDecode(rawColorStocks);
      } catch (e) {
        AppLog.d('Error decoding color_stocks JSON string: $e');
      }
    }

    if (rawColorStocks is List) {
      for (final entry in rawColorStocks) {
        if (entry == null) continue;
        Map<dynamic, dynamic>? mapEntry;
        if (entry is Map) {
          mapEntry = entry;
        } else if (entry is String && entry.isNotEmpty) {
          try {
            final decoded = jsonDecode(entry);
            if (decoded is Map) {
              mapEntry = decoded;
            }
          } catch (_) {}
        }
        if (mapEntry == null) continue;

        final name = (mapEntry['color']?.toString() ?? '').trim();
        final qty = (mapEntry['quantity'] as num?)?.toInt() ?? 0;
        if (name.isEmpty) continue;
        colorStocks.add(ProductColorStock(
          color: name,
          quantity: qty < 0 ? 0 : qty,
        ));
      }
    }

    return Product(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? 'Unknown',
      code: json['code'] ?? '',
      category: json['category'] ?? 'Uncategorized',
      quantity: json['quantity'] ?? 0,
      threshold: json['threshold'] ?? 10,
      supplierId: json['supplier_id']?.toString() ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      costPrice: (json['cost_price'] as num?)?.toDouble(),
      imageUrl: json['image_url'] ?? (imagesList.isNotEmpty ? imagesList.first.url : null),
      images: imagesList,
      unit: json['unit'],
      colorStocks: colorStocks,
      description: json['description'],
      stockStatus: _mapStatus(json['stock_status']),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']).toLocal() : null,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']).toLocal() : null,
    );
  }

  StockStatus _mapStatus(String? status) {
    switch (status) {
      case 'low_stock':
        return StockStatus.lowStock;
      case 'out_of_stock':
        return StockStatus.outOfStock;
      default:
        return StockStatus.inStock;
    }
  }

  @override
  void dispose() {
    _subscription?.unsubscribe();
    super.dispose();
  }
}
