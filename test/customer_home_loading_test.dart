import 'dart:async';

import 'package:bersolek_mart_mobile/core/auth/auth_controller.dart';
import 'package:bersolek_mart_mobile/core/network/api_client.dart';
import 'package:bersolek_mart_mobile/core/storage/secure_store.dart';
import 'package:bersolek_mart_mobile/features/customer/customer_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SlowOptionalApi extends ApiClient {
  _SlowOptionalApi({this.holdProducts = false}) : super(SecureStore());

  final bool holdProducts;
  final Completer<dynamic> products = Completer<dynamic>();
  final Completer<dynamic> categories = Completer<dynamic>();
  final Completer<dynamic> cms = Completer<dynamic>();

  @override
  Future<String> baseUrl() async => ApiClient.defaultBaseUrl;

  @override
  Future<dynamic> get(
    String path, {
    Map<String, String>? query,
    bool auth = true,
  }) {
    switch (path) {
      case '/catalog/products':
        final response = {
          'ok': true,
          'data': [
            {
              'id': 17,
              'name': 'Produk Uji',
              'price': 12500,
              'sale_price': null,
              'image': '/assets/demo/products/default.svg',
              'status': 'active',
              'store_name': 'UMKM Uji',
            },
          ],
        };
        return holdProducts ? products.future : Future<dynamic>.value(response);
      case '/catalog/categories':
        return categories.future;
      case '/cms/home':
        return cms.future;
      default:
        throw StateError('Unexpected API request: $path');
    }
  }
}

void main() {
  testWidgets(
    'products render while optional CMS and category requests are still pending',
    (tester) async {
      final api = _SlowOptionalApi();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWith((ref) => api)],
          child: const MaterialApp(home: Scaffold(body: CustomerHome())),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Produk UMKM Lokal'), findsOneWidget);
      expect(find.text('Produk Uji'), findsOneWidget);
      expect(find.text('Server mengembalikan katalog kosong. Coba kata kunci atau kategori lain.'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );
  testWidgets(
    'member home keeps search and product skeleton visible while product API is pending',
    (tester) async {
      final api = _SlowOptionalApi(holdProducts: true);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWith((ref) => api)],
          child: const MaterialApp(home: Scaffold(body: CustomerHome())),
        ),
      );
      await tester.pump();

      // It must not regress to a single centered spinner/blank screen during a slow API call.
      expect(find.text('Produk UMKM Lokal'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Memuat katalog dari server…'), findsOneWidget);
      expect(find.byType(Card).evaluate().length, greaterThanOrEqualTo(4));

      api.products.complete({
        'ok': true,
        'data': [
          {
            'id': 17,
            'name': 'Produk Uji',
            'price': 12500,
            'sale_price': null,
            'image': '/assets/demo/products/default.svg',
            'status': 'active',
            'store_name': 'UMKM Uji',
          },
        ],
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Produk Uji'), findsOneWidget);
      expect(find.text('Memuat katalog dari server…'), findsNothing);
    },
  );

}
