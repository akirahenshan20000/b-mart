import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bersolek_mart_mobile/shared/widgets/brand_bottom_navigation.dart';

void main() {
  const items = [
    BrandNavItem('Beranda', Icons.home_outlined, Icons.home),
    BrandNavItem('Kategori', Icons.grid_view_outlined, Icons.grid_view),
    BrandNavItem('Keranjang', Icons.shopping_bag_outlined, Icons.shopping_bag),
    BrandNavItem('Pesanan', Icons.receipt_long_outlined, Icons.receipt_long),
    BrandNavItem('Akun', Icons.person_outline, Icons.person),
  ];

  for (final width in [320.0, 390.0, 520.0]) {
    testWidgets('bottom menu fits a $width px viewport', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 700);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var selected = -1;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          bottomNavigationBar: BrandBottomNavigation(
            selectedIndex: 0,
            items: items,
            onSelected: (index) => selected = index,
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('Keranjang'), findsOneWidget);
      await tester.tap(find.text('Keranjang'));
      expect(selected, 2);
      expect(tester.takeException(), isNull);
    });
  }
}
