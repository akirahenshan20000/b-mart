import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';
import '../storage/secure_store.dart';

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(ref.read(secureStoreProvider)));

class Session {
  final Map<String, dynamic> user;
  final String token;

  const Session({required this.user, required this.token});

  String get role => (user['level'] ?? '').toString();
  bool get isDriver => role == 'driver';
  bool get isCustomer => role == 'konsumen' || role == 'customer';
}

class AuthController extends AsyncNotifier<Session?> {
  ApiClient get _api => ref.read(apiClientProvider);
  SecureStore get _store => ref.read(secureStoreProvider);

  @override
  Future<Session?> build() async {
    final token = await _store.readToken();
    if (token == null || token.isEmpty) return null;
    try {
      final payload = await _api.get('/me');
      final user = Map<String, dynamic>.from(payload['data'] as Map);
      final session = Session(user: user, token: token);
      if (!session.isCustomer && !session.isDriver) {
        await _store.deleteToken();
        return null;
      }
      return session;
    } catch (_) {
      await _store.deleteToken();
      return null;
    }
  }

  Future<void> login(String login, String password, String deviceName) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final payload = await _api.post(
        '/auth/login',
        {
          'login': login.trim(),
          'password': password,
          'device_name': deviceName,
        },
        auth: false,
      );

      final data = Map<String, dynamic>.from(payload['data'] as Map);
      final token = '${data['token']}';
      final user = Map<String, dynamic>.from(data['user'] as Map);
      final session = Session(user: user, token: token);
      if (!session.isCustomer && !session.isDriver) {
        throw ApiException(403, 'Akun administrator/operator/merchant tidak dapat masuk ke aplikasi mobile.');
      }
      await _store.saveToken(token);
      return session;
    });
  }

  Future<void> logout() async {
    final token = await _store.readToken();
    if (token != null && token.isNotEmpty) {
      try {
        await _api.post('/auth/logout', {}, auth: true);
      } catch (_) {
        // Local logout must still complete when the server is unavailable.
      }
    }
    await _store.deleteToken();
    state = const AsyncData(null);
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, Session?>(AuthController.new);
