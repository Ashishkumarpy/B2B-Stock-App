import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../logging/app_log.dart';
import '../utils/connection_messages.dart';

class ServerApiClient {
  final String baseUrl;

  /// Current access token. Mutable so a transparent refresh can update it for
  /// the retry without recreating the client.
  String? token;

  /// Called when a request gets a 401. Should attempt to obtain a fresh access
  /// token (via the refresh token) and return it, or null if refresh failed.
  /// Deduplication of concurrent refreshes is the callback's responsibility.
  final Future<String?> Function()? onRefresh;

  /// Called when authentication is unrecoverable (refresh failed). Typically
  /// clears the session and routes the user to login.
  final Future<void> Function()? onUnauthorized;

  ServerApiClient({
    required this.baseUrl,
    this.token,
    this.onRefresh,
    this.onUnauthorized,
  });

  /// Lightweight, unauthenticated warm-up request to `/health`. Best-effort:
  /// never throws. Used to wake a cold-started backend (e.g. Render free tier
  /// spins down when idle) so the first real data call isn't blocked behind a
  /// 30-60s spin-up. Fire-and-forget from app startup.
  Future<void> ping() async {
    try {
      await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 60));
    } catch (_) {
      // Warm-up only — the request still reaches Render and triggers the
      // spin-up even if it times out or fails locally.
    }
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  /// Runs [send] (which builds a request from the current headers), and on a
  /// 401 transparently refreshes the access token and retries exactly once.
  Future<dynamic> _withAuthRetry(
    String path,
    Future<http.Response> Function() send,
  ) async {
    try {
      http.Response response = await send();

      if (response.statusCode == 401 && onRefresh != null) {
        final newToken = await onRefresh!();
        if (newToken != null && newToken.isNotEmpty) {
          token = newToken;
          response = await send(); // retry with refreshed token
        }
        if (response.statusCode == 401) {
          // Refresh unavailable or still rejected -> unrecoverable.
          await onUnauthorized?.call();
        }
      }

      return _handleResponse(response);
    } catch (e) {
      if (e is ServerApiException) rethrow;
      AppLog.d('$path failed: $e');
      if (e is http.ClientException || e is SocketException) {
        throw ServerApiException(connectionWarningMessage, 0);
      }
      rethrow;
    }
  }

  Future<dynamic> get(String path) {
    return _withAuthRetry(
      'GET $path',
      () => http.get(Uri.parse('$baseUrl$path'), headers: _headers),
    );
  }

  Future<dynamic> getJson(String path) => get(path);

  Future<dynamic> post(String path, dynamic body) {
    final encoded = jsonEncode(body);
    return _withAuthRetry(
      'POST $path',
      () => http.post(Uri.parse('$baseUrl$path'),
          headers: _headers, body: encoded),
    );
  }

  Future<dynamic> postJson(String path, dynamic body) => post(path, body);

  Future<dynamic> uploadFile(String path, String filePath) {
    return _withAuthRetry('Multipart POST $path', () async {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'));
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      request.files.add(await http.MultipartFile.fromPath('file', filePath));
      final streamedResponse = await request.send();
      return http.Response.fromStream(streamedResponse);
    });
  }

  Future<dynamic> patch(String path, dynamic body) {
    final encoded = jsonEncode(body);
    return _withAuthRetry(
      'PATCH $path',
      () => http.patch(Uri.parse('$baseUrl$path'),
          headers: _headers, body: encoded),
    );
  }

  Future<dynamic> putJson(String path, dynamic body) {
    final encoded = jsonEncode(body);
    return _withAuthRetry(
      'PUT $path',
      () => http.put(Uri.parse('$baseUrl$path'),
          headers: _headers, body: encoded),
    );
  }

  Future<dynamic> delete(String path) {
    return _withAuthRetry(
      'DELETE $path',
      () => http.delete(Uri.parse('$baseUrl$path'), headers: _headers),
    );
  }

  Future<dynamic> deleteJson(String path) => delete(path);

  dynamic _handleResponse(http.Response response) {
    final body =
        response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    } else {
      final error = body['error'] ?? body['message'] ?? 'Unknown server error';
      AppLog.d('Server Error (${response.statusCode}): $error');
      throw ServerApiException(error, response.statusCode);
    }
  }
}

class ServerApiException implements Exception {
  final String message;
  final int statusCode;
  ServerApiException(this.message, this.statusCode);
  @override
  String toString() => message;
}

typedef ServerException = ServerApiException;
