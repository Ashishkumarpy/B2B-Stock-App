import 'package:b2b_stock_app/core/constants/app_constants.dart';
import 'package:b2b_stock_app/core/theme/app_theme.dart';
import 'package:b2b_stock_app/domain/entities/app_user.dart';
import 'package:b2b_stock_app/domain/entities/product.dart';
import 'package:b2b_stock_app/presentation/providers/auth_provider.dart';
import 'package:b2b_stock_app/presentation/providers/products_provider.dart';
import 'package:b2b_stock_app/presentation/providers/transactions_provider.dart';
import 'package:b2b_stock_app/presentation/screens/products/product_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows product price on product detail screen', (tester) async {
    const product = Product(
      id: 'product-1',
      name: 'Test Mug',
      code: 'MUG-001',
      category: 'Mugs',
      quantity: 120,
      threshold: 10,
      price: 285,
      pcsPerCarton: 12,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productsProvider.overrideWith(
            (ref) => _FakeProductsNotifier(const AsyncValue.data([product])),
          ),
          productTransactionsProvider.overrideWith((ref, productId) => []),
          currentUserProvider.overrideWithValue(
            const AppUser(
              id: 'user-1',
              name: 'Manager',
              email: 'manager@example.com',
              role: UserRole.manager,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const ProductDetailScreen(productId: 'product-1'),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Price'), findsOneWidget);
    expect(find.text('₹285'), findsOneWidget);
  });
}

class _FakeProductsNotifier extends StateNotifier<AsyncValue<List<Product>>>
    implements ProductsNotifier {
  _FakeProductsNotifier(super.state);

  @override
  Future<void> fetchProducts() async {}
}
