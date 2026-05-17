import '../../domain/entities/product.dart';
import '../../domain/entities/transaction.dart' as t_entity;
import '../../domain/entities/supplier.dart';
import '../../domain/entities/warehouse.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/server_api_client.dart';

/// Converts server JSON responses ↔ domain entities.
class ServerDataSource {
  ServerDataSource(this._api);

  final ServerApiClient _api;

  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value.isUtc ? value.toLocal() : value;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed == null) return DateTime.now();
      return parsed.isUtc ? parsed.toLocal() : parsed;
    }
    return DateTime.now();
  }

  Future<List<Product>> fetchProducts() async {
    final json = await _api.getJson('/products');
    final list = (json as Map)['data'] as List? ?? [];
    return list.map((e) => _productFromRow(e as Map<String, dynamic>)).toList();
  }

  Future<Product> createProduct(Map<String, dynamic> payload) async {
    final json = await _api.postJson('/products', payload);
    final row = (json as Map)['data'] as Map<String, dynamic>;
    return _productFromRow(row);
  }

  Future<Product> updateProduct(String id, Map<String, dynamic> payload) async {
    final json = await _api.putJson('/products/$id', payload);
    final row = (json as Map)['data'] as Map<String, dynamic>;
    return _productFromRow(row);
  }

  Future<void> deleteProduct(String id) async {
    await _api.deleteJson('/products/$id');
  }

  static Product _productFromRow(Map<String, dynamic> d) {
    List<ProductImage> images = [];
    final rawImages = d['images'];
    if (rawImages is List) {
      images = rawImages
          .map((img) {
            if (img is Map<String, dynamic>) return ProductImage.fromMap(img);
            if (img is Map) {
              return ProductImage.fromMap(Map<String, dynamic>.from(img));
            }
            if (img is String) return ProductImage(url: img, publicId: '');
            return const ProductImage(url: '', publicId: '');
          })
          .where((image) => image.url.isNotEmpty)
          .toList();
    }

    final colorStocks = <ProductColorStock>[];
    final rawColorStocks = d['color_stocks'];
    if (rawColorStocks is List) {
      for (final entry in rawColorStocks) {
        if (entry is! Map) continue;
        final name = (entry['color'] as String? ?? '').trim();
        final qty = (entry['quantity'] as num?)?.toInt() ?? 0;
        if (name.isEmpty) continue;
        colorStocks.add(ProductColorStock(
          color: name,
          quantity: qty < 0 ? 0 : qty,
        ));
      }
    }

    return Product(
      id: d['id'] as String,
      name: d['name'] as String? ?? '',
      code: d['code'] as String? ?? '',
      category: d['category'] as String? ?? 'Uncategorized',
      description: d['description'] as String?,
      quantity: (d['quantity'] as num?)?.toInt() ?? 0,
      threshold: (d['threshold'] as num?)?.toInt() ?? 10,
      supplierId: d['supplier_id'] as String? ?? '',
      price: (d['price'] as num?)?.toDouble() ?? 0.0,
      costPrice: (d['cost_price'] as num?)?.toDouble(),
      imageUrl: d['image_url'] as String?,
      images: images,
      unit: d['unit'] as String?,
      colorStocks: colorStocks,
      updatedAt: _parseDate(d['updated_at']),
      createdAt: _parseDate(d['created_at']),
    );
  }

  static Map<String, dynamic> productToRow(Product p) => {
        'id': p.id,
        'name': p.name,
        'code': p.sku,
        'category': p.category,
        'description': p.description,
        'quantity': p.quantity,
        'threshold': p.threshold,
        'supplier_id': p.supplierId.isEmpty ? null : p.supplierId,
        'price': p.price,
        if (p.costPrice != null) 'cost_price': p.costPrice,
        'image_url': p.imageUrl,
        'images': p.images
            .where((image) => image.url.trim().isNotEmpty)
            .map((image) => image.toMap())
            .toList(),
        if (p.unit != null) 'unit': p.unit,
        'color_stocks': p.colorStocks
            .map((entry) => {
                  'color': entry.color.trim(),
                  'quantity': entry.quantity,
                })
            .where((entry) => (entry['color'] as String).isNotEmpty)
            .toList(),
        'updated_at': (p.updatedAt ?? DateTime.now()).toIso8601String(),
      };

  // Placeholder for future endpoints
  Future<List<t_entity.Transaction>> fetchTransactions() async {
    final json = await _api.getJson('/transactions');
    final list = (json as Map)['data'] as List? ?? [];
    return list.map((e) => _txnFromRow(e as Map<String, dynamic>)).toList();
  }

  Future<void> createTransaction(Map<String, dynamic> payload) async {
    await _api.postJson('/transactions', payload);
  }

  Future<List<Supplier>> fetchSuppliers() async {
    final json = await _api.getJson('/suppliers');
    final list = (json as Map)['data'] as List? ?? [];
    return list
        .map((e) => _supplierFromRow(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Warehouse>> fetchWarehouses(
      {bool includeInactive = false}) async {
    try {
      final json = await _api.getJson(includeInactive
          ? '/warehouses?include_inactive=true'
          : '/warehouses');
      final list = (json as Map)['data'] as List? ?? [];
      return list
          .map((e) => _warehouseFromRow(e as Map<String, dynamic>))
          .toList();
    } on ServerApiException catch (e) {
      if (e.statusCode == 404) {
        return const <Warehouse>[];
      }
      rethrow;
    }
  }

  Future<Warehouse> createWarehouse(Map<String, dynamic> payload) async {
    final json = await _api.postJson('/warehouses', payload);
    final row = (json as Map)['data'] as Map<String, dynamic>;
    return _warehouseFromRow(row);
  }

  Future<Warehouse> updateWarehouse(
      String id, Map<String, dynamic> payload) async {
    final json = await _api.putJson('/warehouses/$id', payload);
    final row = (json as Map)['data'] as Map<String, dynamic>;
    return _warehouseFromRow(row);
  }

  static t_entity.Transaction _txnFromRow(Map<String, dynamic> d) {
    return t_entity.Transaction(
      id: d['id'] as String,
      productId: d['product_id'] as String? ?? '',
      workerId: d['worker_id'] as String? ?? d['user_id'] as String? ?? '',
      productName: d['product_name'] as String? ?? '',
      workerName: d['worker_name'] as String? ?? '',
      colorName: d['color_name'] as String?,
      warehouseId: d['warehouse_id'] as String?,
      warehouseName: d['warehouse_name'] as String?,
      type: TransactionType.fromString(d['type'] as String? ?? 'IN'),
      quantity: (d['quantity'] as num?)?.toInt() ?? 0,
      notes: d['notes'] as String?,
      createdAt: _parseDate(d['created_at']),
    );
  }

  static Map<String, dynamic> txnToRow(t_entity.Transaction t) => {
        'product_id': t.productId,
        // Server resolves worker_id/worker_name/product_name.
        'type': t.type == TransactionType.stockIn ? 'stock_in' : 'stock_out',
        'quantity': t.quantity,
        if (t.colorName != null && t.colorName!.trim().isNotEmpty)
          'color_name': t.colorName!.trim(),
        if (t.warehouseId != null && t.warehouseId!.trim().isNotEmpty)
          'warehouse_id': t.warehouseId!.trim(),
        'created_at': t.createdAt.toUtc().toIso8601String(),
        if (t.notes != null) 'notes': t.notes,
      };

  static Supplier _supplierFromRow(Map<String, dynamic> d) {
    return Supplier(
      id: d['id'] as String,
      name: d['name'] as String? ?? '',
      contactName: '',
      email: d['contact_email'] as String? ?? '',
      phone: d['contact_phone'] as String? ?? '',
      address: null,
      productIds: const [],
      createdAt: _parseDate(d['created_at']),
    );
  }

  static Warehouse _warehouseFromRow(Map<String, dynamic> d) {
    return Warehouse(
      id: d['id'] as String,
      name: d['name'] as String? ?? '',
      code: d['code'] as String?,
      location: d['location'] as String?,
      locationUrl: d['location_url'] as String?,
      isActive: d['is_active'] as bool? ?? true,
      createdAt: _parseDate(d['created_at']),
    );
  }
}
