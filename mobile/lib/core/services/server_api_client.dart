import 'dart:convert';
import 'package:http/http.dart' as http;
import '../logging/app_log.dart';

class ServerApiClient {
  final String baseUrl;
  final String? token;

  ServerApiClient({required this.baseUrl, this.token});

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> get(String path) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl$path'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      AppLog.d('GET $path failed: $e');
      rethrow;
    }
  }

  Future<dynamic> getJson(String path) => get(path);

  Future<dynamic> post(String path, dynamic body) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl$path'),
        headers: _headers,
        body: jsonEncode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      AppLog.d('POST $path failed: $e');
      rethrow;
    }
  }

  Future<dynamic> postJson(String path, dynamic body) => post(path, body);

  Future<dynamic> uploadFile(String path, String filePath) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'));
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      request.files.add(await http.MultipartFile.fromPath('file', filePath));
      
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      return _handleResponse(response);
    } catch (e) {
      AppLog.d('Multipart POST $path failed: $e');
      rethrow;
    }
  }

  Future<dynamic> patch(String path, dynamic body) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl$path'),
        headers: _headers,
        body: jsonEncode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      AppLog.d('PATCH $path failed: $e');
      rethrow;
    }
  }

  Future<dynamic> putJson(String path, dynamic body) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl$path'),
        headers: _headers,
        body: jsonEncode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      AppLog.d('PUT $path failed: $e');
      rethrow;
    }
  }

  Future<dynamic> delete(String path) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl$path'),
        headers: _headers,
      );
      return _handleResponse(response);
    } catch (e) {
      AppLog.d('DELETE $path failed: $e');
      rethrow;
    }
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
