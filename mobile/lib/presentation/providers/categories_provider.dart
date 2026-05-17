import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'products_provider.dart';

final categoriesProvider = Provider<AsyncValue<List<String>>>((ref) {
  final productsAsync = ref.watch(productsProvider);
  
  return productsAsync.when(
    data: (products) {
      final categories = products
          .map((p) => p.category)
          .where((c) => c.isNotEmpty)
          .toSet()
          .toList();
      categories.sort();
      return AsyncValue.data(categories);
    },
    loading: () => const AsyncValue.loading(),
    error: (err, stack) => AsyncValue.error(err, stack),
  );
});

final categorySummaryProvider = Provider.family<AsyncValue<CategorySummary>, String>((ref, categoryName) {
  final productsAsync = ref.watch(productsProvider);
  
  return productsAsync.when(
    data: (products) {
      final categoryProducts = products.where((p) => p.category == categoryName).toList();
      final totalQty = categoryProducts.fold<int>(0, (sum, p) => sum + p.quantity);
      final lowStockCount = categoryProducts.where((p) => p.quantity <= p.threshold).length;
      
      final productWithImage = categoryProducts.where((p) => p.imageUrl != null).firstOrNull;
      final sampleImage = productWithImage?.imageUrl;
      
      return AsyncValue.data(CategorySummary(
        name: categoryName,
        productCount: categoryProducts.length,
        totalQuantity: totalQty,
        lowStockCount: lowStockCount,
        sampleImageUrl: sampleImage,
      ));
    },
    loading: () => const AsyncValue.loading(),
    error: (err, stack) => AsyncValue.error(err, stack),
  );
});

class CategorySummary {
  final String name;
  final int productCount;
  final int totalQuantity;
  final int lowStockCount;
  final String? sampleImageUrl;

  CategorySummary({
    required this.name,
    required this.productCount,
    required this.totalQuantity,
    required this.lowStockCount,
    this.sampleImageUrl,
  });

  factory CategorySummary.empty(String name) => CategorySummary(
        name: name,
        productCount: 0,
        totalQuantity: 0,
        lowStockCount: 0,
      );
}
