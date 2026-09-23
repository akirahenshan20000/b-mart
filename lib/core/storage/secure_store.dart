import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  static const _tokenKey = 'api_token';
  static const _baseUrlKey = 'api_base_url';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> saveToken(String token) => _storage.write(key: _tokenKey, value: token);
  Future<String?> readToken() => _storage.read(key: _tokenKey);
  Future<void> deleteToken() => _storage.delete(key: _tokenKey);

  Future<void> saveBaseUrl(String value) => _storage.write(key: _baseUrlKey, value: value);
  Future<String?> readBaseUrl() => _storage.read(key: _baseUrlKey);
}
