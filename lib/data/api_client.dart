import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_http_client.dart';

class ApiException implements Exception {
  ApiException(this.status, this.code, this.message);

  final int status;

  /// Stable machine code from the server (e.g. `not_your_turn`), or
  /// `network` when the server could not be reached.
  final String code;
  final String message;

  @override
  String toString() => message;
}

/// Thin client for the PHP backend: JSON in, JSON out, bearer token auth.
class ApiClient {
  ApiClient(this.baseUrl, {http.Client? client, this.token}) : _http = client ?? createApiHttpClient();

  final String baseUrl;
  final http.Client _http;
  String? token;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> get(String path) => _send(() => _http.get(Uri.parse('$baseUrl$path'), headers: _headers));

  Future<Map<String, dynamic>> post(String path, [Map<String, dynamic> body = const {}]) =>
      _send(() => _http.post(Uri.parse('$baseUrl$path'), headers: _headers, body: jsonEncode(body)));

  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) =>
      _send(() => _http.patch(Uri.parse('$baseUrl$path'), headers: _headers, body: jsonEncode(body)));

  Future<Map<String, dynamic>> upload(String path, Uint8List bytes, String filename) => _send(() async {
        final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'))
          ..headers.addAll({if (token != null) 'Authorization': 'Bearer $token'})
          ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
        return http.Response.fromStream(await _http.send(request));
      });

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() request) async {
    final http.Response response;
    try {
      response = await request().timeout(const Duration(seconds: 12));
    } catch (e) {
      throw ApiException(0, 'network', 'Cannot reach the server. Check your connection.');
    }
    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException(response.statusCode, 'bad_response', 'Unexpected reply from the server');
    }
    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, data['error'] as String? ?? 'error',
          data['message'] as String? ?? 'Request failed');
    }
    return data;
  }

  void close() => _http.close();
}
