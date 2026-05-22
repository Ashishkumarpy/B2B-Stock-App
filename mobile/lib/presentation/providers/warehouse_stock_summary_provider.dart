import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client_provider.dart';

final warehouseStockSummaryProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final json = await client.get('/warehouses/stock-summary');
  final list = (json is Map ? json['data'] : null) as List? ?? const [];
  return list
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
});
