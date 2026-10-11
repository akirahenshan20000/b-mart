import 'package:bersolek_mart_mobile/features/driver/driver_shell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Driver road-navigation leg follows the existing delivery workflow', () {
    test('does not route before assignment or after arrival/delivery completion', () {
      expect(driverNavigationLegForStatus('available'), isNull);
      expect(driverNavigationLegForStatus('arrived'), isNull);
      expect(driverNavigationLegForStatus('delivered'), isNull);
      expect(driverNavigationLegForStatus('completed'), isNull);
    });

    test('routes to merchant until pickup and to customer while delivering', () {
      expect(driverNavigationLegForStatus('assigned'), 'pickup');
      expect(driverNavigationLegForStatus('accepted'), 'pickup');
      expect(driverNavigationLegForStatus('picking_up'), 'pickup');
      expect(driverNavigationLegForStatus('picked_up'), 'dropoff');
      expect(driverNavigationLegForStatus('delivering'), 'dropoff');
    });

    test('delivery proof stage is not confused with final completion', () {
      DriverJobView job(String status) => DriverJobView(
        id: '42',
        code: 'BM-42',
        status: status,
        storeName: 'UMKM',
        customerName: 'Pelanggan',
        pickupAddress: 'Alamat merchant',
        dropoffAddress: 'Alamat pelanggan',
        price: 12000,
        pickup: null,
        dropoff: null,
      );

      expect(job('delivered').isCompleted, isFalse);
      expect(job('delivered').statusLabel, 'Bukti Pengantaran');
      expect(job('completed').isCompleted, isTrue);
      expect(job('completed').statusLabel, 'Selesai');
    });
  });
}
