import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/auth/auth_controller.dart';

Map<String, dynamic> _baseData(dynamic payload) =>
    payload is Map && payload['data'] is Map
        ? Map<String, dynamic>.from(payload['data'] as Map)
        : payload is Map
            ? Map<String, dynamic>.from(payload)
            : <String, dynamic>{};

class DriverBaseLocationPage extends ConsumerStatefulWidget {
  const DriverBaseLocationPage({super.key});

  @override
  ConsumerState<DriverBaseLocationPage> createState() => _DriverBaseLocationPageState();
}

class _DriverBaseLocationPageState extends ConsumerState<DriverBaseLocationPage> {
  late Future<Map<String, dynamic>> _future;
  Position? _position;
  double _radius = 5;
  bool _locating = false;
  bool _saving = false;
  String? _message;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final result = _baseData(await ref.read(apiClientProvider).get('/driver/profile'));
    final radius = double.tryParse(result['service_radius_km']?.toString() ?? '');
    if (mounted && radius != null && radius >= 1 && radius <= 30) _radius = radius;
    return result;
  }

  Future<void> _captureGps() async {
    setState(() {
      _locating = true;
      _message = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw StateError('Izin lokasi ditolak. Aktifkan izin lokasi presisi untuk menyimpan titik pangkal.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
      );
      if (!mounted) return;
      setState(() {
        _position = position;
        _message = 'GPS didapat. Akurasi ${position.accuracy.toStringAsFixed(0)} meter.';
        _success = true;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error is StateError ? error.message : 'Lokasi gagal didapat. Periksa izin perangkat dan coba lagi.';
          _success = false;
        });
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save({required bool useDefaultAddress}) async {
    if (!useDefaultAddress && _position == null) {
      setState(() {
        _message = 'Ambil lokasi GPS terlebih dahulu.';
        _success = false;
      });
      return;
    }
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await ref.read(apiClientProvider).post('/driver/base-location', {
        'source': useDefaultAddress ? 'address' : 'driver_gps',
        if (!useDefaultAddress) 'lat': _position!.latitude,
        if (!useDefaultAddress) 'lng': _position!.longitude,
        if (!useDefaultAddress) 'accuracy': _position!.accuracy,
        'service_radius_km': _radius.round(),
      });
      if (!mounted) return;
      setState(() {
        _future = _load();
        _message = useDefaultAddress
            ? 'Titik pangkal dari alamat utama berhasil disimpan oleh server.'
            : 'Titik pangkal GPS berhasil disimpan oleh server.';
        _success = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'Titik pangkal gagal disimpan. Pastikan API driver/base-location sudah terpasang dan alamat utama memiliki koordinat jika menggunakan alamat.';
          _success = false;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Alamat dan Titik Pangkal')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off_outlined, size: 46, color: Color(0xFF147D58)),
                const SizedBox(height: 12),
                const Text('Data profil driver belum dapat dimuat dari API.'),
                const SizedBox(height: 10),
                OutlinedButton.icon(onPressed: () => setState(() => _future = _load()), icon: const Icon(Icons.refresh), label: const Text('Coba lagi')),
              ]),
            ),
          );
        }
        final data = snapshot.data ?? const <String, dynamic>{};
        final lat = double.tryParse(data['base_lat']?.toString() ?? '');
        final lng = double.tryParse(data['base_lng']?.toString() ?? '');
        final address = (data['base_address_snapshot'] ?? '').toString().trim();
        final source = (data['base_source'] ?? '').toString().trim();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Titik pangkal saat ini', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text(lat != null && lng != null ? '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}' : 'Belum ditetapkan'),
                  if (address.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5), child: Text(address, style: const TextStyle(color: Colors.black54))),
                  if (source.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5), child: Text('Sumber: ${source == 'driver_gps' ? 'GPS driver' : source}', style: const TextStyle(color: Colors.black54, fontSize: 12))),
                  if (data['base_updated_at'] != null) Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text('Diperbarui: ${data['base_updated_at']}', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Radius layanan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            Text('${_radius.round()} km', style: const TextStyle(color: Colors.black54)),
            Slider(value: _radius.clamp(1, 30).toDouble(), min: 1, max: 30, divisions: 29, label: '${_radius.round()} km', onChanged: (value) => setState(() => _radius = value)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _locating ? null : _captureGps,
              icon: _locating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location_rounded),
              label: Text(_locating ? 'Mengambil GPS…' : 'Ambil lokasi GPS saat ini'),
            ),
            if (_position != null) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('GPS perangkat: ${_position!.latitude.toStringAsFixed(6)}, ${_position!.longitude.toStringAsFixed(6)} · akurasi ${_position!.accuracy.toStringAsFixed(0)} m',
                style: const TextStyle(color: Colors.black54, fontSize: 12)),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _saving ? null : () => _save(useDefaultAddress: false),
              icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Menyimpan…' : 'Simpan titik GPS'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _saving ? null : () => _save(useDefaultAddress: true),
              icon: const Icon(Icons.home_work_outlined),
              label: const Text('Gunakan alamat utama yang memiliki GPS'),
            ),
            if (_message != null) Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _success ? const Color(0xFFE6F5ED) : const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_message!, style: TextStyle(color: _success ? const Color(0xFF147D58) : const Color(0xFFB00020))),
              ),
            ),
            const SizedBox(height: 10),
            const Text('Koordinat dan radius disimpan ke profil driver di backend. Lokasi tidak dikarang jika GPS atau alamat berkoordinat belum tersedia.',
              style: TextStyle(color: Colors.black54, height: 1.4)),
          ],
        );
      },
    ),
  );
}
