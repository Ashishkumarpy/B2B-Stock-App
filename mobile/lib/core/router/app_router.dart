import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../presentation/screens/auth/login_screen.dart';
import '../../presentation/screens/main_shell.dart';
import '../../presentation/screens/dashboard/dashboard_screen.dart';
import '../../presentation/screens/products/product_list_screen.dart';
import '../../presentation/screens/products/product_detail_screen.dart';
import '../../presentation/screens/products/add_product_screen.dart';
import '../../presentation/screens/products/bulk_import_products_screen.dart';
import '../../domain/entities/product.dart';
import '../../presentation/screens/stock/stock_entry_screen.dart';
import '../../presentation/screens/analytics/analytics_screen.dart';
import '../../presentation/screens/dashboard/worker_activity_screen.dart';
import '../../presentation/screens/dashboard/worker_detail_screen.dart';
import '../../presentation/screens/dashboard/stock_activity_screen.dart';
import '../../presentation/screens/settings/settings_screen.dart';
import '../../presentation/screens/settings/create_worker_screen.dart';
import '../../presentation/providers/auth_provider.dart';
import '../../presentation/providers/server_base_url_provider.dart';
import '../../presentation/screens/settings/server_config_screen.dart';
import '../../presentation/screens/settings/debug_logs_screen.dart';
import '../../presentation/screens/settings/manage_workers_screen.dart';
import '../../presentation/screens/settings/manage_warehouses_screen.dart';
import '../constants/app_constants.dart';
import '../logging/app_log.dart';

class _RouterRefreshNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefreshNotifier();

  // Keep a single GoRouter instance; trigger refresh when auth/server changes.
  ref.listen(authStateProvider, (_, __) => refresh.notify());
  ref.listen(serverBaseUrlProvider, (_, __) => refresh.notify());

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refresh,
    debugLogDiagnostics: true,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final serverBaseUrl = ref.read(serverBaseUrlProvider);
      final path = state.uri.path;
      final isOnServerConfig = path == '/server';
      final isOnLogs = path == '/debug-logs';
      final isOnLogin = path == '/login';
      if (serverBaseUrl.isEmpty && !isOnServerConfig && !isOnLogin) return '/server';

      final isLoggedIn = authState.user != null;
      final role = authState.user?.role;
      final isAdminOnlyRoute = path == '/add-product' ||
          path == '/bulk-import-products' ||
          path == '/manage-workers' ||
          path == '/create-worker';
      final isWarehouseManageRoute = path == '/manage-warehouses';

      // Allow accessing Server config and Login without an active session.
      if (!isLoggedIn && !isOnLogin && !isOnServerConfig && !isOnLogs) {
        AppLog.d('redirect → /login (from $path)');
        return '/login';
      }
      if (isLoggedIn &&
          (role == UserRole.worker || role == UserRole.manager) &&
          isAdminOnlyRoute) {
        return '/';
      }
      if (isLoggedIn && role == UserRole.worker && isWarehouseManageRoute) {
        return '/';
      }
      if (isLoggedIn && isOnLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/server',
        pageBuilder: (context, state) => _buildPage(
          state,
          const ServerConfigScreen(),
        ),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _buildPage(
          state,
          const LoginScreen(),
        ),
      ),
      GoRoute(
        path: '/debug-logs',
        pageBuilder: (context, state) => _buildPage(
          state,
          const DebugLogsScreen(),
        ),
      ),
      GoRoute(
        path: '/create-worker',
        pageBuilder: (context, state) => _buildPage(
          state,
          const CreateWorkerScreen(),
        ),
      ),
      GoRoute(
        path: '/manage-workers',
        pageBuilder: (context, state) => _buildPage(
          state,
          const ManageWorkersScreen(),
        ),
      ),
      GoRoute(
        path: '/manage-warehouses',
        pageBuilder: (context, state) => _buildPage(
          state,
          const ManageWarehousesScreen(),
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) =>
                _buildPage(state, const DashboardScreen()),
          ),
          GoRoute(
            path: '/products',
            pageBuilder: (context, state) {
              final filter = state.uri.queryParameters['filter'];
              return _buildPage(
                  state, ProductListScreen(initialFilter: filter));
            },
            routes: [
              GoRoute(
                path: ':id',
                pageBuilder: (context, state) {
                  final id = state.pathParameters['id']!;
                  return _buildPage(state, ProductDetailScreen(productId: id));
                },
              ),
            ],
          ),
          GoRoute(
            path: '/stock-entry',
            pageBuilder: (context, state) {
              final productId = state.uri.queryParameters['productId'];
              final typeRaw = state.uri.queryParameters['type'];
              final initialType = switch (typeRaw) {
                'in' => TransactionType.stockIn,
                'out' => TransactionType.stockOut,
                _ => null,
              };
              return _buildPage(
                state,
                StockEntryScreen(
                    productId: productId, initialType: initialType),
              );
            },
          ),
          GoRoute(
            path: '/add-product',
            pageBuilder: (context, state) =>
                _buildPage(state, const AddProductScreen()),
          ),
          GoRoute(
            path: '/bulk-import-products',
            pageBuilder: (context, state) =>
                _buildPage(state, const BulkImportProductsScreen()),
          ),
          GoRoute(
            path: '/edit-product',
            pageBuilder: (context, state) {
              final product = state.extra as Product?;
              return _buildPage(
                  state, AddProductScreen(productToEdit: product));
            },
          ),
          GoRoute(
            path: '/analytics',
            pageBuilder: (context, state) =>
                _buildPage(state, const AnalyticsScreen()),
          ),
          GoRoute(
            path: '/worker-activity',
            pageBuilder: (context, state) =>
                _buildPage(state, const WorkerActivityScreen()),
          ),
          GoRoute(
            path: '/stock-activity',
            pageBuilder: (context, state) {
              final type = state.uri.queryParameters['type'];
              final dateMode = state.uri.queryParameters['dateMode'];
              final date = state.uri.queryParameters['date'];
              return _buildPage(
                state,
                StockActivityScreen(
                  initialType: type,
                  initialDateMode: dateMode,
                  initialDate: date,
                ),
              );
            },
          ),
          GoRoute(
            path: '/worker-detail/:userId',
            pageBuilder: (context, state) => _buildPage(state,
                WorkerDetailScreen(userId: state.pathParameters['userId']!)),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) =>
                _buildPage(state, const SettingsScreen()),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Page not found: ${state.uri}\n\nError: ${state.error}',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
});

CustomTransitionPage<void> _buildPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurveTween(curve: Curves.easeInOut).animate(animation),
        child: child,
      );
    },
    transitionDuration: const Duration(milliseconds: 220),
  );
}
