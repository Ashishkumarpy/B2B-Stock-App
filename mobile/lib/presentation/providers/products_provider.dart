import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/product.dart';
import '../../core/constants/app_constants.dart';
import '../../core/logging/app_log.dart';
import '../../core/services/server_api_client.dart';
import '../../core/utils/connection_messages.dart';
import 'api_client_provider.dart';

final productsProvider =
    StateNotifierProvider<ProductsNotifier, AsyncValue<List<Product>>>((ref) {
  return ProductsNotifier(ref.watch(apiClientProvider));
});

class ProductsNotifier extends StateNotifier<AsyncValue<List<Product>>> {
  ProductsNotifier([this._client]) : super(const AsyncValue.loading()) {
    _init();
  }

  final ServerApiClient? _client;
  Timer? _refreshTimer;

  Future<void> _init() async {
    await fetchProducts();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _fetchProducts(silent: true),
    );
  }

  Future<void> fetchProducts() => _fetchProducts();

  Future<void> _fetchProducts({bool silent = false}) async {
    try {
      if (!silent) state = const AsyncValue.loading();

      final client = _client;
      if (client == null) {
        throw ServerApiException(connectionWarningMessage, 0);
      }

      final json = await client.get('/products?limit=1000&page=1');
      final rows = (json is Map ? json['data'] : null) as List? ?? const [];
      final products = rows
          .whereType<Map>()
          .map((row) => _mapToProduct(Map<String, dynamic>.from(row)))
          .toList();
      state = AsyncValue.data(products);
    } catch (e, st) {
      AppLog.d('Error fetching products: $e');
      if (!silent || !state.hasValue) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Product _mapToProduct(Map<String, dynamic> json) {
    // Mapping from Supabase Snake Case to Dart Camel Case
    final imagesList = (json['images'] as List?)
            ?.map((i) => ProductImage.fromMap(i as Map<String, dynamic>))
            .toList() ??
        [];

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
      pcsPerCarton: (json['pcs_per_carton'] as num?)?.toInt(),
      imageUrl: json['image_url'] ??
          (imagesList.isNotEmpty ? imagesList.first.url : null),
      images: imagesList,
      unit: json['unit'],
      colorStocks: colorStocks,
      description: json['description'],
      stockStatus: _mapStatus(json['stock_status']),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at']).toLocal()
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at']).toLocal()
          : null,
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
    _refreshTimer?.cancel();
    super.dispose();
  }
}
