import 'dart:convert';

import 'package:http/http.dart' as http;

import '../storage/secure_store.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final String? code;

  ApiException(this.statusCode, this.message, {this.code});

  @override
  String toString() => 'ApiException($statusCode, $message)';
}

class ApiClient {
  ApiClient(this._store);

  final SecureStore _store;

  static const defaultBaseUrl = 'https://bersolekmart.com/api/v1';

  Future<String> baseUrl() async {
    final saved = await _store.readBaseUrl();
    if (saved == null || saved.trim().isEmpty) return defaultBaseUrl;
    final normalized = _normalize(saved);
    if (normalized.contains('10.0.2.2') || normalized.contains('localhost') || normalized.contains('127.0.0.1')) {
      return defaultBaseUrl;
    }
    return normalized;
  }

  Future<void> saveBaseUrl(String value) => _store.saveBaseUrl(_normalize(value));

  String _normalize(String raw) {
    var value = raw.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  Future<Map<String, String>> _headers({bool jsonBody = false, bool auth = true}) async {
    final headers = <String, String>{
      'Accept': 'application/json',
    };
    if (jsonBody) headers['Content-Type'] = 'application/json';
    if (auth) {
      final token = await _store.readToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  Future<dynamic> get(String path, {Map<String, String>? query, bool auth = true}) async {
    final uri = Uri.parse('${await baseUrl()}$path').replace(queryParameters: query);
    final response = await http.get(uri, headers: await _headers(auth: auth));
    return _parse(response);
  }

  Future<dynamic> post(String path, Map<String, dynamic> body, {bool auth = true}) async {
    final uri = Uri.parse('${await baseUrl()}$path');
    final response = await http.post(
      uri,
      headers: await _headers(jsonBody: true, auth: auth),
      body: jsonEncode(body),
    );
    return _parse(response);
  }

  dynamic _parse(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }

    final ok = response.statusCode >= 200 && response.statusCode < 300;
    if (!ok) {
      final error = decoded is Map ? decoded['error'] : null;
      final message = error is Map ? '${error['message'] ?? 'API request failed'}' : 'API request failed';
      final code = error is Map ? '${error['code'] ?? ''}' : null;
      throw ApiException(response.statusCode, message, code: code);
    }

    if (decoded is Map && decoded['ok'] == false) {
      final error = decoded['error'];
      throw ApiException(response.statusCode, '${error is Map ? error['message'] : 'API request failed'}');
    }

    return decoded;
  }
}
