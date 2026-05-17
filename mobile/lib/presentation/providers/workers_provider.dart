import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client_provider.dart';

/// Fetches workers list from the Node server (authenticated).
final workersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final res = await client.get('/workers');
  final data = res['data'] as List<dynamic>? ?? [];
  return data.cast<Map<String, dynamic>>();
});
