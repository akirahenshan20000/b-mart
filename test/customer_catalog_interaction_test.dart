import 'package:bersolek_mart_mobile/core/auth/auth_controller.dart';
import 'package:bersolek_mart_mobile/core/network/api_client.dart';
import 'package:bersolek_mart_mobile/core/storage/secure_store.dart';
import 'package:bersolek_mart_mobile/features/customer/customer_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _CatalogApi extends ApiClient {
  _CatalogApi() : super(SecureStore());
  final List<Map<String, String>> productQueries = [];

  @override
  Future<String> baseUrl() async => ApiClient.defaultBaseUrl;

  @override
  Future<dynamic> get(String path, {Map<String, String>? query, bool auth = true}) async {
    if (path == '/catalog/products') {
      productQueries.add(Map<String, String>.from(query ?? const {}));
      return {'ok': true, 'data': [
        {'id': 31, 'name': 'Kerupuk Ikan', 'price': 15000,
         'status': 'active', 'store_name': 'Toko Cahaya', 'image': ''}
      ]};
    }
    if (path == '/catalog/categories') {
      return {'ok': true, 'data': [
        {'id': 8, 'name': 'Kuliner', 'slug': 'Kuliner', 'status': 'active'}
      ]};
    }
    if (path == '/cms/home') return {'ok': true, 'data': {'hero_slides': []}};
    throw StateError('Unexpected request: $path');
  }
}

void main() {
  testWidgets('search and category tiles reload the catalog with API filters', (tester) async {
    final api = _CatalogApi();
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWith((ref) => api)],
      child: const MaterialApp(home: Scaffold(body: CustomerHome())),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Kerupuk');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(api.productQueries.last['q'], 'Kerupuk');

    await tester.tap(find.text('Kuliner'));
    await tester.pumpAndSettle();
    expect(api.productQueries.last['category'], 'Kuliner');
    expect(tester.takeException(), isNull);
  });
}
