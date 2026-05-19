import 'package:equatable/equatable.dart';
import '../../core/constants/app_constants.dart';

class ProductImage extends Equatable {
  final String url;
  final String publicId;

  const ProductImage({
    required this.url,
    required this.publicId,
  });

  factory ProductImage.fromMap(Map<String, dynamic> map) {
    return ProductImage(
      url: map['url'] ?? '',
      publicId: map['publicId'] ?? map['public_id'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'publicId': publicId,
    };
  }

  @override
  List<Object?> get props => [url, publicId];
}

class ProductColorStock extends Equatable {
  final String color;
  final int quantity;

  const ProductColorStock({
    required this.color,
    required this.quantity,
  });

  factory ProductColorStock.fromMap(Map<String, dynamic> map) {
    return ProductColorStock(
      color: map['color']?.toString() ?? '',
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'color': color,
      'quantity': quantity,
    };
  }

  @override
  List<Object?> get props => [color, quantity];
}

class Product extends Equatable {
  final String id;
  final String name;
  final String code;
  final String category;
  final int quantity;
  final int threshold;
  final String supplierId;
  final double price;
  final double? costPrice;
  final int? pcsPerCarton;
  final String? imageUrl;
  final List<ProductImage> images;
  final List<ProductColorStock> colorStocks;
  final String? unit;
  final String? description;
  final StockStatus stockStatus;
  final DateTime? updatedAt;
  final DateTime? createdAt;

  const Product({
    required this.id,
    required this.name,
    String? code,
    String? sku,
    required this.category,
    this.quantity = 0,
    this.threshold = 10,
    this.supplierId = '',
    this.price = 0.0,
    this.costPrice,
    this.pcsPerCarton,
    this.imageUrl,
    this.images = const [],
    this.colorStocks = const [],
    this.unit,
    this.description,
    this.stockStatus = StockStatus.inStock,
    this.updatedAt,
    this.createdAt,
  }) : code = code ?? sku ?? '';

  String get sku => code;

  Product copyWith({
    String? id,
    String? name,
    String? code,
    String? category,
    int? quantity,
    int? threshold,
    String? supplierId,
    double? price,
    double? costPrice,
    int? pcsPerCarton,
    String? imageUrl,
    List<ProductImage>? images,
    List<ProductColorStock>? colorStocks,
    String? unit,
    String? description,
    StockStatus? stockStatus,
    DateTime? updatedAt,
    DateTime? createdAt,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      threshold: threshold ?? this.threshold,
      supplierId: supplierId ?? this.supplierId,
      price: price ?? this.price,
      costPrice: costPrice ?? this.costPrice,
      pcsPerCarton: pcsPerCarton ?? this.pcsPerCarton,
      imageUrl: imageUrl ?? this.imageUrl,
      images: images ?? this.images,
      colorStocks: colorStocks ?? this.colorStocks,
      unit: unit ?? this.unit,
      description: description ?? this.description,
      stockStatus: stockStatus ?? this.stockStatus,
      updatedAt: updatedAt ?? this.updatedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        code,
        category,
        quantity,
        threshold,
        supplierId,
        price,
        costPrice,
        pcsPerCarton,
        imageUrl,
        images,
        colorStocks,
        unit,
        description,
        stockStatus,
        updatedAt,
        createdAt,
      ];
}
