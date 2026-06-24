import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/transaction.dart';
import '../../core/constants/app_constants.dart';
import '../../core/logging/app_log.dart';
import '../../core/services/server_api_client.dart';
import 'api_client_provider.dart';
import 'products_provider.dart';
import 'server_session_provider.dart';
import 'transactions_provider.dart';

/// Everything the dashboard renders, fetched in a single `/dashboard` request
/// instead of fanning out to /products, /transactions and
/// /warehouses/stock-summary separately.
class DashboardData {
  final List<Product> products;
  final List<Transaction> transactions;
  final List<Map<String, dynamic>> warehouses;

  const DashboardData({
    required this.products,
    required this.transactions,
    required this.warehouses,
  });

  const DashboardData.empty()
      : products = const [],
        transactions = const [],
        warehouses = const [];
}

final dashboardProvider =
    StateNotifierProvider<DashboardNotifier, AsyncValue<DashboardData>>((ref) {
  return DashboardNotifier(ref);
});

class DashboardNotifier extends StateNotifier<AsyncValue<DashboardData>> {
  DashboardNotifier(this._ref) : super(const AsyncValue.loading()) {
    _init();
    // This notifier reads the API client lazily (not via watch), so it isn't
    // recreated when the token rotates. That means it would otherwise miss a
    // fresh login — so refetch when the session goes from signed-out to
    // signed-in. A token *rotation* (non-empty -> non-empty) is ignored to
    // avoid a redundant fetch alongside pull-to-refresh.
    _ref.listen<ServerSession?>(serverSessionProvider, (prev, next) {
      final wasAuthed = (prev?.token ?? '').isNotEmpty;
      final isAuthed = (next?.token ?? '').isNotEmpty;
      if (!wasAuthed && isAuthed) fetch();
    });
  }

  // Read the API client lazily per request (instead of watching it at
  // construction) so a token refresh doesn't recreate this notifier and trigger
  // a redundant refetch.
  final Ref _ref;
  Timer? _refreshTimer;

  static const _cacheKey = 'cache_dashboard_v1';

  Future<void> _init() async {
    final hadCache = _loadFromCache();
    await fetch(silent: hadCache);
    _startPolling();
  }

  /// Background 30s refresh — only while we hold an access token, so we don't
  /// spin out guaranteed-401 polls for a logged-out / unrenewable session.
  void _startPolling() {
    _refreshTimer?.cancel();
    final client = _ref.read(apiClientProvider);
    if ((client.token ?? '').isEmpty) return;
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => fetch(silent: true),
    );
  }

  /// Foreground refresh (e.g. pull-to-refresh).
  Future<void> refresh() => fetch();

  bool _loadFromCache() {
    try {
      final box = Hive.box(AppConstants.settingsBox);
      final cached = box.get(_cacheKey) as String?;
      if (cached == null || cached.isEmpty) return false;
      final decoded = jsonDecode(cached);
      if (decoded is! Map) return false;
      final data = _parse(decoded);
      if (data.products.isEmpty &&
          data.transactions.isEmpty &&
          data.warehouses.isEmpty) {
        return false;
      }
      state = AsyncValue.data(data);
      return true;
    } catch (e) {
      AppLog.d('Error loading cached dashboard: $e');
      return false;
    }
  }

  void _saveToCache(Map<String, dynamic> payload) {
    try {
      Hive.box(AppConstants.settingsBox).put(_cacheKey, jsonEncode(payload));
    } catch (e) {
      AppLog.d('Error caching dashboard: $e');
    }
  }

  Future<void> fetch({bool silent = false}) async {
    final client = _ref.read(apiClientProvider);

    // Not authenticated (logged out, or a session that can't be refreshed):
    // don't hammer the server with guaranteed-401 polls and keep cached data.
    if ((client.token ?? '').isEmpty) {
      _refreshTimer?.cancel();
      if (!state.hasValue) state = const AsyncValue.data(DashboardData.empty());
      return;
    }

    try {
      if (!silent) state = const AsyncValue.loading();

      final json = await client.get('/dashboard');
      final map = json is Map
          ? Map<String, dynamic>.from(json)
          : <String, dynamic>{};
      state = AsyncValue.data(_parse(map));
      _saveToCache(map);
      // Auth may have just been restored — make sure polling is running.
      if (_refreshTimer == null || !_refreshTimer!.isActive) _startPolling();
    } on ServerApiException catch (e) {
      AppLog.d('Error fetching dashboard: $e');
      // A 401 means the session expired and couldn't be refreshed — stop the
      // background poll so we don't spam the server. A connection error
      // (statusCode 0) is transient, so leave polling to retry. Either way keep
      // cached data instead of surfacing an error.
      if (e.statusCode == 401) _refreshTimer?.cancel();
      if (!state.hasValue) state = const AsyncValue.data(DashboardData.empty());
    } catch (e, st) {
      AppLog.d('Error fetching dashboard: $e');
      if (!silent && !state.hasValue) state = AsyncValue.error(e, st);
    }
  }

  DashboardData _parse(Map source) {
    final productRows = (source['products'] as List?) ?? const [];
    final txRows = (source['transactions'] as List?) ?? const [];
    final warehouseRows = (source['warehouses'] as List?) ?? const [];

    final products = productRows
        .whereType<Map>()
        .map((row) => productFromRow(Map<String, dynamic>.from(row)))
        .toList();
    final transactions = txRows
        .whereType<Map>()
        .map((row) => transactionFromRow(Map<String, dynamic>.from(row)))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final warehouses = warehouseRows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    return DashboardData(
      products: products,
      transactions: transactions,
      warehouses: warehouses,
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
