import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/server_api_client.dart';
import 'server_base_url_provider.dart';
import 'server_session_provider.dart';

final apiClientProvider = Provider<ServerApiClient>((ref) {
  final baseUrl = ref.watch(serverBaseUrlProvider);
  final session = ref.watch(serverSessionProvider);

  return ServerApiClient(
    baseUrl: baseUrl,
    token: session?.token,
  );
});
