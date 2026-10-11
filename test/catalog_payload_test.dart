import 'package:flutter_test/flutter_test.dart';
import 'package:bersolek_mart_mobile/features/customer/customer_shell.dart';

void main() {
  group('catalogProductsFromPayload', () {
    test('accepts a valid server response containing products', () {
      final products = catalogProductsFromPayload({
        'ok': true,
        'data': [
          {'id': 7, 'name': 'Produk UMKM', 'price': 12000, 'image': '/uploads/p.jpg', 'status': 'active'},
        ],
      });

      expect(products, hasLength(1));
      expect(products.first['id'], 7);
    });

    test('preserves a valid empty response as an empty catalog', () {
      expect(catalogProductsFromPayload({'ok': true, 'data': []}), isEmpty);
    });

    test('does not turn a failed or malformed response into an empty catalog', () {
      expect(
        () => catalogProductsFromPayload({'ok': false, 'error': {'message': 'failed'}}),
        throwsFormatException,
      );
      expect(
        () => catalogProductsFromPayload({'ok': true, 'data': {'items': []}}),
        throwsFormatException,
      );
      expect(
        () => catalogProductsFromPayload({'ok': true, 'data': [{'id': 1}]}),
        throwsFormatException,
      );
    });
  });

  group('resolveMediaUrl', () {
    const base = 'https://bersolekmart.com/api/v1';

    test('resolves root-relative paths against the production origin', () {
      expect(
        resolveMediaUrl('/uploads/products/photo.webp', base),
        'https://bersolekmart.com/uploads/products/photo.webp',
      );
    });

    test('preserves absolute URLs and supports protocol-relative CDN URLs', () {
      expect(
        resolveMediaUrl('https://cdn.example.test/photo.webp', base),
        'https://cdn.example.test/photo.webp',
      );
      expect(
        resolveMediaUrl('//cdn.example.test/photo.webp', base),
        'https://cdn.example.test/photo.webp',
      );
    });
  });
}
