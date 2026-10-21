import 'package:bersolek_mart_mobile/core/auth/auth_controller.dart';
import 'package:bersolek_mart_mobile/core/network/api_client.dart';
import 'package:bersolek_mart_mobile/core/storage/secure_store.dart';
import 'package:bersolek_mart_mobile/features/customer/customer_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemberApi extends ApiClient {
  _MemberApi() : super(SecureStore());
  bool removed = false;

  @override
  Future<String> baseUrl() async => ApiClient.defaultBaseUrl;

  @override
  Future<dynamic> get(String path, {Map<String, String>? query, bool auth = true}) async {
    if (path == '/orders') return {'ok': true, 'data': [
      {'id': 42, 'code': 'BM-42', 'total': 15000, 'status': 'processing'}
    ]};
    if (path == '/orders/42') return {'ok': true, 'data': {
      'id': 42, 'code': 'BM-42', 'status': 'processing',
      'subtotal': 12000, 'shipping_total': 3000, 'total': 15000,
      'shipping_method': 'SOPIR', 'payment_method': 'qris',
      'items': [
        {'product_name_snapshot': 'Kopi Lokal', 'qty': 2, 'unit_price': 6000, 'line_total': 12000}
      ]
    }};
    if (path == '/cart') return {'ok': true, 'data': {
      'items': removed ? [] : [
        {'id': '7', 'line_key': '7', 'qty': 1, 'name': 'Kopi Lokal',
         'unit_price': 6000, 'store_name': 'UMKM', 'image': ''}
      ],
      'count': removed ? 0 : 1,
      'subtotal': removed ? 0 : 6000,
    }};
    throw StateError('Unexpected API request: $path');
  }

  @override
  Future<dynamic> post(String path, Map<String, dynamic> body, {bool auth = true}) async {
    if (path != '/cart/remove' || body['item_id'] != 7) {
      throw StateError('Cart remove contract mismatch: $path $body');
    }
    removed = true;
    return {'ok': true, 'data': {'items': [], 'count': 0, 'subtotal': 0}};
  }
}

void main() {
  testWidgets('member can open ordered products from the order list', (tester) async {
    final api = _MemberApi();
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWith((ref) => api)],
      child: const MaterialApp(home: Scaffold(body: CustomerOrders())),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BM-42'));
    await tester.pumpAndSettle();
    expect(find.text('Kopi Lokal'), findsOneWidget);
    expect(find.text('2 × Rp 6.000'), findsOneWidget);
    expect(find.text('Rp 15.000'), findsWidgets);
  });

  testWidgets('member can remove cart line using a numeric item ID', (tester) async {
    final api = _MemberApi();
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWith((ref) => api)],
      child: MaterialApp(home: CustomerCart(onContinueShopping: () {})),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Hapus produk'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(api.removed, isTrue);
    // Ignore: diagnostic output while validating asynchronous cart refresh.
    // ignore: avoid_print
    print(tester.widgetList<Text>(find.byType(Text)).map((widget) => widget.data).toList());
    expect(find.text('Keranjang masih kosong'), findsOneWidget);
  });
}
