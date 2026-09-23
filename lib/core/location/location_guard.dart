import 'dart:async';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

import '../network/api_client.dart';

class LocationSnapshot {
  final Position position;
  final bool mocked;
  final bool movementAnomaly;
  final double? calculatedSpeedKmh;
  final String? note;

  const LocationSnapshot({
    required this.position,
    required this.mocked,
    required this.movementAnomaly,
    required this.calculatedSpeedKmh,
    required this.note,
  });
}

class LocationGuard {
  LocationGuard(this._api);

  final ApiClient _api;
  StreamSubscription<Position>? _subscription;
  Position? _previous;

  final _controller = StreamController<LocationSnapshot>.broadcast();
  Stream<LocationSnapshot> get stream => _controller.stream;

  Future<void> start() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Location service pada perangkat belum aktif.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw StateError('Izin lokasi belum diberikan.');
    }

    await stop();

    const settings = AndroidSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 10,
      intervalDuration: Duration(seconds: 8),
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationTitle: 'BersolekMart Driver aktif',
        notificationText: 'Validasi lokasi sedang berjalan.',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );

    _subscription = Geolocator.getPositionStream(locationSettings: settings).listen(
      _handlePosition,
      onError: (Object error, StackTrace stack) {
        _controller.addError(error, stack);
      },
    );
  }

  Future<void> _handlePosition(Position position) async {
    final previous = _previous;
    final calculatedSpeed = previous == null ? null : _speedKmh(previous!, position);
    final anomaly = calculatedSpeed != null && calculatedSpeed > 180;
    final mocked = position.isMocked;

    final snapshot = LocationSnapshot(
      position: position,
      mocked: mocked,
      movementAnomaly: anomaly,
      calculatedSpeedKmh: calculatedSpeed,
      note: mocked
          ? 'Mock location terdeteksi oleh Android/provider.'
          : anomaly
              ? 'Perpindahan lokasi tidak wajar terdeteksi.'
              : null,
    );
    _controller.add(snapshot);

    if (mocked) return;

    final payload = <String, dynamic>{
      'lat': position.latitude,
      'lng': position.longitude,
      'accuracy': position.accuracy,
      'speed_mps': position.speed,
      'speed_accuracy_mps': position.speedAccuracy,
      'bearing': position.heading,
      'captured_at': position.timestamp.toUtc().toIso8601String(),
      'is_mocked': false,
      'movement_anomaly': anomaly,
    };

    try {
      await _api.post('/driver/location', payload);
    } catch (_) {
      // Location stream continues; UI can surface network status separately.
    }

    _previous = position;
  }

  double _speedKmh(Position a, Position b) {
    final meters = _distanceMeters(a.latitude, a.longitude, b.latitude, b.longitude);
    final seconds = b.timestamp.difference(a.timestamp).inMilliseconds / 1000.0;
    if (seconds <= 0) return 0;
    return (meters / seconds) * 3.6;
  }

  double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _rad(double value) => value * math.pi / 180.0;

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
