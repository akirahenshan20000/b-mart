import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/location/location_guard.dart';
import '../../core/network/api_client.dart';

class DriverShell extends ConsumerStatefulWidget {
  const DriverShell({super.key});
  @override
  ConsumerState<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends ConsumerState<DriverShell> {
  int _index = 0;
  late final LocationGuard _guard;
  StreamSubscription<LocationSnapshot>? _locationSubscription;
  LocationSnapshot? _lastSnapshot;
  bool _running = false;
  bool _serverHealthy = false;

  @override
  void initState() {
    super.initState();
    _guard = LocationGuard(ref.read(apiClientProvider));
    _locationSubscription = _guard.stream.listen((snapshot) {
      if (!mounted) return;
      setState(() => _lastSnapshot = snapshot);
      if (snapshot.mocked && _running) {
        _showMockWarning();
      }
    }, onError: (Object error) {
      if (!mounted) return;
      setState(() => _serverHealthy = false);
    });
  }

  Future<void> _toggleGuard() async {
    if (_running) {
      await _guard.stop();
      setState(() => _running = false);
      return;
    }
    try {
      await _guard.start();
      setState(() => _running = true);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location Guard aktif.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _showMockWarning() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.red, content: Text('Mock location terdeteksi. Sinkronisasi lokasi dihentikan.')));
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DriverDashboard(running: _running, snapshot: _lastSnapshot, onToggle: _toggleGuard),
      const DriverJobs(),
      const DriverProfile(),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('BersolekMart Driver')),
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.gps_not_fixed), selectedIcon: Icon(Icons.gps_fixed), label: 'Lokasi'),
          NavigationDestination(icon: Icon(Icons.local_shipping_outlined), selectedIcon: Icon(Icons.local_shipping), label: 'Job'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _guard.dispose();
    super.dispose();
  }
}

class DriverDashboard extends StatelessWidget {
  const DriverDashboard({super.key, required this.running, required this.snapshot, required this.onToggle});
  final bool running;
  final LocationSnapshot? snapshot;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final mocked = snapshot?.mocked ?? false;
    final anomaly = snapshot?.movementAnomaly ?? false;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _LocationCard(running: running, mocked: mocked, anomaly: anomaly, snapshot: snapshot),
        const SizedBox(height: 14),
        FilledButton.icon(onPressed: mocked ? null : onToggle, icon: Icon(running ? Icons.stop_circle_outlined : Icons.play_circle_outline), label: Text(running ? 'Hentikan Location Guard' : 'Mulai Location Guard')),
        const SizedBox(height: 14),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [Text('Fase anti-mock'), Text('APK membaca flag mock dari provider Android, menahan pengiriman lokasi ketika terdeteksi, dan mengirim evidence lokasi ke API existing. Server-side continuity/geofence dan Play Integrity akan menjadi lapisan berikutnya.', style: TextStyle(color: Colors.black54))]))),
      ],
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.running, required this.mocked, required this.anomaly, required this.snapshot});
  final bool running;
  final bool mocked;
  final bool anomaly;
  final LocationSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    Color bg;
    String title;
    IconData icon;
    if (mocked) {
      bg = Colors.red.shade100;
      title = 'MOCK LOCATION TERDETEKSI';
      icon = Icons.location_off;
    } else if (anomaly) {
      bg = Colors.orange.shade100;
      title = 'PERGERAKAN TIDAK WAJAR';
      icon = Icons.warning_amber_rounded;
    } else if (running) {
      bg = Colors.green.shade100;
      title = 'LOCATION GUARD AKTIF';
      icon = Icons.location_on;
    } else {
      bg = Colors.blueGrey.shade50;
      title = 'LOCATION GUARD BELUM AKTIF';
      icon = Icons.gps_not_fixed;
    }

    final position = snapshot?.position;
    return Card(color: bg, child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon), const SizedBox(width: 10), Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)))]),
      const SizedBox(height: 16),
      _kv('Latitude', position == null ? '-' : position.latitude.toStringAsFixed(7)),
      _kv('Longitude', position == null ? '-' : position.longitude.toStringAsFixed(7)),
      _kv('Accuracy', position == null ? '-' : '${position.accuracy.toStringAsFixed(1)} m'),
      _kv('Speed', position == null ? '-' : '${(position.speed * 3.6).toStringAsFixed(1)} km/h'),
      _kv('Mocked', mocked ? 'YES' : 'NO'),
    ])));
  }

  Widget _kv(String key, String value) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [SizedBox(width: 110, child: Text(key, style: const TextStyle(color: Colors.black54))), Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700)))]));
}

class DriverJobs extends ConsumerStatefulWidget {
  const DriverJobs({super.key});
  @override
  ConsumerState<DriverJobs> createState() => _DriverJobsState();
}

class _DriverJobsState extends ConsumerState<DriverJobs> {
  late Future<List<dynamic>> _future;
  @override
  void initState() { super.initState(); _future = _load(); }
  Future<List<dynamic>> _load() async {
    final payload = await ref.read(apiClientProvider).get('/driver/jobs');
    return List<dynamic>.from(payload['data'] as List);
  }
  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => setState(() => _future = _load()),
      child: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('${snapshot.error}', textAlign: TextAlign.center)));
          final items = snapshot.data ?? const [];
          if (items.isEmpty) return ListView(children: const [SizedBox(height: 140), Center(child: Text('Belum ada job driver.'))]);
          return ListView.separated(padding: const EdgeInsets.all(16), itemCount: items.length, separatorBuilder: (_, __) => const SizedBox(height: 10), itemBuilder: (context, index) {
            final job = Map<String, dynamic>.from(items[index] as Map);
            return Card(child: ListTile(isThreeLine: true, leading: CircleAvatar(child: Text('${job['id']}')), title: Text('${job['order_code'] ?? 'Order'}'), subtitle: Text('${job['store_name'] ?? '-'}\nStatus: ${job['status'] ?? '-'}'), trailing: const Icon(Icons.chevron_right)));
          });
        },
      ),
    );
  }
}

class DriverProfile extends ConsumerWidget {
  const DriverProfile({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).valueOrNull;
    final user = session?.user ?? const <String, dynamic>{};
    return ListView(padding: const EdgeInsets.all(16), children: [
      CircleAvatar(radius: 40, child: Text('${(user['full_name'] ?? 'D').toString().substring(0, 1).toUpperCase()}')),
      const SizedBox(height: 14),
      Center(child: Text('${user['full_name'] ?? '-'}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
      Center(child: Text('Driver', style: const TextStyle(color: Colors.black54))),
      const SizedBox(height: 24),
      FilledButton.tonalIcon(onPressed: () => ref.read(authControllerProvider.notifier).logout(), icon: const Icon(Icons.logout), label: const Text('Keluar')),
    ]);
  }
}
