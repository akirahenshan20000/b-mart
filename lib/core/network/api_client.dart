import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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

String apiErrorMessage(Object error) {
  if (error is ApiException) {
    switch ((error.code ?? '').toUpperCase()) {
      case 'INVALID_CREDENTIALS':
        return 'Username/email atau password tidak sesuai.';
      case 'RATE_LIMITED':
        return 'Terlalu banyak percobaan masuk. Tunggu sebentar lalu coba lagi.';
      case 'ROLE_NOT_SUPPORTED':
        return 'Jenis akun ini tidak dapat digunakan pada aplikasi mobile.';
      case 'FORBIDDEN':
        return 'Akun ini tidak memiliki akses ke layanan yang dipilih.';
      case 'AUTH_REQUIRED':
        return 'Sesi login berakhir. Silakan masuk kembali.';
      case 'API_DISABLED':
        return 'Layanan mobile sedang dinonaktifkan. Coba lagi nanti.';
      case 'REQUEST_TIMEOUT':
        return 'Server merespons terlalu lama. Periksa koneksi lalu coba lagi.';
      case 'NETWORK_ERROR':
        return 'Server tidak dapat dijangkau. Periksa koneksi internet.';
    }
    final message = error.message.trim();
    final hasUsefulMessage =
        message.isNotEmpty && !message.startsWith('ApiException(') && message != 'API request failed';
    // Preserve explicit role-mismatch errors raised by the mobile client itself.
    if (error.statusCode == 403 && (error.code == null || error.code!.isEmpty) && hasUsefulMessage) {
      return message;
    }
    if (error.statusCode == 401) return 'Login gagal. Periksa username/email dan password.';
    if (error.statusCode == 403) return 'Akun tidak diizinkan menggunakan layanan ini.';
    if (error.statusCode == 404) return 'Endpoint layanan belum tersedia pada server.';
    if (error.statusCode >= 500) return 'Server sedang mengalami kendala. Coba lagi nanti.';
    if (hasUsefulMessage) return message;
  }
  if (error is TimeoutException) {
    return 'Server merespons terlalu lama. Periksa koneksi lalu coba lagi.';
  }
  return 'Terjadi kendala saat menghubungi server. Coba lagi.';
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

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw ApiException(
        0,
        'Koneksi ke server terlalu lama. Periksa internet lalu coba lagi.',
        code: 'REQUEST_TIMEOUT',
      );
    } on http.ClientException {
      throw ApiException(
        0,
        'Tidak dapat terhubung ke server BersolekMart. Periksa koneksi internet.',
        code: 'NETWORK_ERROR',
      );
    }
  }

  void _debugResponse(String method, Uri uri, http.Response response) {
    if (!kDebugMode) return;
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }

    String shape;
    if (decoded is Map) {
      final data = decoded['data'];
      if (data is List) {
        shape = 'object(data=list:${data.length})';
      } else if (data is Map) {
        shape = 'object(data=object keys:${data.keys.take(10).join(',')})';
      } else {
        shape = 'object(keys:${decoded.keys.take(10).join(',')}, data:${data.runtimeType})';
      }
    } else if (decoded is List) {
      shape = 'list:${decoded.length}';
    } else {
      shape = 'non-json-or-null';
    }

    // Never log authorization headers, payload values, or personal data.
    debugPrint(
      '[BersolekMart API] $method ${uri.path} -> HTTP ${response.statusCode}; '
      'bytes=${response.bodyBytes.length}; $shape',
    );
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
    final headers = await _headers(auth: auth);
    final response = await _send(() => http.get(uri, headers: headers));
    _debugResponse('GET', uri, response);
    return _parse(response);
  }

  Future<dynamic> post(String path, Map<String, dynamic> body, {bool auth = true}) async {
    final uri = Uri.parse('${await baseUrl()}$path');
    final headers = await _headers(jsonBody: true, auth: auth);
    final encodedBody = jsonEncode(body);
    final response = await _send(
      () => http.post(uri, headers: headers, body: encodedBody),
    );
    _debugResponse('POST', uri, response);
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
      throw ApiException(
        response.statusCode,
        message,
        code: code == null || code.isEmpty ? null : code,
      );
    }

    if (decoded is Map && decoded['ok'] == false) {
      final error = decoded['error'];
      final message = error is Map ? '${error['message'] ?? 'API request failed'}' : 'API request failed';
      final code = error is Map ? '${error['code'] ?? ''}' : '';
      throw ApiException(
        response.statusCode,
        message,
        code: code.isEmpty ? null : code,
      );
    }

    return decoded;
  }
}
