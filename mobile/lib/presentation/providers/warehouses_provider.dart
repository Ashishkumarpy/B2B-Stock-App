import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client_provider.dart';

/// Fetches warehouses list from the Node server (authenticated).
final warehousesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, bool>(
        (ref, includeInactive) async {
  final client = ref.watch(apiClientProvider);
  final res = await client.get(
    includeInactive ? '/warehouses?include_inactive=true' : '/warehouses',
  );
  final data = res['data'] as List<dynamic>? ?? [];
  return data.cast<Map<String, dynamic>>();
});

final activeWarehousesProvider = warehousesProvider(false);
final allWarehousesProvider = warehousesProvider(true);
