import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bersolek_mart_mobile/features/customer/customer_shell.dart';

void main() {
  group('catalog formatting and media URL helpers', () {
    test('formats Rupiah without decimal digits', () {
      expect(formatRupiah(15000), 'Rp 15.000');
      expect(formatRupiah('8000.00'), 'Rp 8.000');
      expect(formatRupiah(null), 'Rp 0');
    });

    test('handles empty or malformed API product responses without throwing', () {
      expect(catalogProductsFromPayload({'ok': true, 'data': []}), isEmpty);
      expect(catalogProductsFromPayload({'ok': true, 'data': null}), isEmpty);
      expect(catalogProductsFromPayload(null), isEmpty);
    });

    test('resolves root-relative production media paths', () {
      expect(
        resolveMediaUrl('/uploads/products/item.jpg', 'https://bersolekmart.com/api/v1'),
        'https://bersolekmart.com/uploads/products/item.jpg',
      );
    });

    test('preserves local XAMPP subdirectory when resolving media', () {
      expect(
        resolveMediaUrl('/uploads/products/item.jpg', 'http://192.168.1.10/bersolekmart/api/v1'),
        'http://192.168.1.10/bersolekmart/uploads/products/item.jpg',
      );
    });

    test('preserves already absolute media URLs', () {
      expect(
        resolveMediaUrl('https://cdn.example.test/item.jpg', 'https://bersolekmart.com/api/v1'),
        'https://cdn.example.test/item.jpg',
      );
    });
  });

  testWidgets('shows a stable fallback for empty or unsupported SVG image paths', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Column(
        children: [
          SizedBox(width: 100, height: 100, child: ProductImageView(path: '', apiBase: 'https://bersolekmart.com/api/v1')),
          SizedBox(width: 100, height: 100, child: ProductImageView(path: '/assets/demo/products/default.svg', apiBase: 'https://bersolekmart.com/api/v1')),
        ],
      ),
    ));

    expect(find.byIcon(Icons.image_not_supported_outlined), findsNWidgets(2));
  });

  testWidgets('shows a fallback when a product image request fails', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SizedBox(
        width: 100,
        height: 100,
        child: ProductImageView(
          path: 'http://127.0.0.1:1/does-not-exist.jpg',
          apiBase: 'https://bersolekmart.com/api/v1',
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
  });
}
