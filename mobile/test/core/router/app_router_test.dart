import 'package:b2b_stock_app/core/constants/app_constants.dart';
import 'package:b2b_stock_app/core/router/app_router.dart';
import 'package:b2b_stock_app/core/theme/app_theme.dart';
import 'package:b2b_stock_app/domain/entities/app_user.dart';
import 'package:b2b_stock_app/domain/entities/product.dart';
import 'package:b2b_stock_app/presentation/providers/auth_provider.dart';
import 'package:b2b_stock_app/presentation/providers/products_provider.dart';
import 'package:b2b_stock_app/presentation/providers/server_base_url_provider.dart';
import 'package:b2b_stock_app/presentation/providers/transactions_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('keeps notification product route while auth is restoring',
      (tester) async {
    const product = Product(
      id: 'product-1',
      name: 'Notification Mug',
      code: 'NOTIFY-001',
      category: 'Mugs',
      quantity: 24,
      threshold: 5,
      price: 125,
    );
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => _FakeAuthNotifier(AuthState(isInitialized: false)),
        ),
        serverBaseUrlProvider.overrideWith(
          (ref) => _FakeServerBaseUrlNotifier('https://example.com'),
        ),
        productsProvider.overrideWith(
          (ref) => _FakeProductsNotifier(const AsyncValue.data([product])),
        ),
        productTransactionsProvider.overrideWith((ref, productId) => []),
      ],
    );
    addTearDown(container.dispose);

    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );

    router.go('/products/product-1');
    await tester.pumpAndSettle();

    expect(find.text('Login'), findsNothing);
    expect(find.text('NOTIFY-001'), findsOneWidget);
  });

  testWidgets('returns to notification product route after login',
      (tester) async {
    const product = Product(
      id: 'product-1',
      name: 'Notification Mug',
      code: 'NOTIFY-001',
      category: 'Mugs',
      quantity: 24,
      threshold: 5,
      price: 125,
    );
    final auth = _FakeAuthNotifier(AuthState(isInitialized: true));
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith((ref) => auth),
        serverBaseUrlProvider.overrideWith(
          (ref) => _FakeServerBaseUrlNotifier('https://example.com'),
        ),
        productsProvider.overrideWith(
          (ref) => _FakeProductsNotifier(const AsyncValue.data([product])),
        ),
        productTransactionsProvider.overrideWith((ref, productId) => []),
      ],
    );
    addTearDown(container.dispose);

    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );

    router.go('/products/product-1');
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'a@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'password');
    await tester.tap(find.text('Log In'));
    await tester.pumpAndSettle();

    expect(find.text('NOTIFY-001'), findsOneWidget);
  });
}

class _FakeAuthNotifier extends StateNotifier<AuthState>
    implements AuthNotifier {
  _FakeAuthNotifier(super.state);

  @override
  Future<bool> login(String email, String password) async {
    state = state.copyWith(
      user: const AppUser(
        id: 'user-1',
        name: 'Admin',
        email: 'a@example.com',
        role: UserRole.admin,
      ),
      isLoading: false,
      isInitialized: true,
    );
    return true;
  }

  @override
  Future<void> logout() async {}

  @override
  Future<(bool, String?)> requestWorkerOtp(String phone) async => (true, null);

  @override
  Future<bool> verifyWorkerOtp(String phone, String otp) async => true;
}

class _FakeServerBaseUrlNotifier extends StateNotifier<String>
    implements ServerBaseUrlNotifier {
  _FakeServerBaseUrlNotifier(super.state);

  @override
  Future<void> setUrl(String url) async {
    state = url;
  }
}

class _FakeProductsNotifier extends StateNotifier<AsyncValue<List<Product>>>
    implements ProductsNotifier {
  _FakeProductsNotifier(super.state);

  @override
  Future<void> fetchProducts() async {}
}
