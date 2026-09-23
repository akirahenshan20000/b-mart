
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/location/location_guard.dart';

class DriverJobView {
  const DriverJobView({
    required this.id,
    required this.code,
    required this.status,
    required this.storeName,
    required this.customerName,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.price,
    required this.pickup,
    required this.dropoff,
  });

  final String id;
  final String code;
  final String status;
  final String storeName;
  final String customerName;
  final String pickupAddress;
  final String dropoffAddress;
  final num? price;
  final LatLng? pickup;
  final LatLng? dropoff;

  bool get isCompleted {
    final value = status.toLowerCase();
    return value.contains('complete') ||
        value.contains('delivered') ||
        value.contains('selesai');
  }

  bool get isActive {
    final value = status.toLowerCase();
    return value.contains('assigned') ||
        value.contains('accepted') ||
        value.contains('picking') ||
        value.contains('picked') ||
        value.contains('delivering') ||
        value.contains('arrived') ||
        value.contains('aktif') ||
        value.contains('antar');
  }

  bool get isNew => !isCompleted && !isActive;
}

class DriverShell extends ConsumerStatefulWidget {
  const DriverShell({super.key});

  @override
  ConsumerState<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends ConsumerState<DriverShell> {
  int _index = 0;
  late final LocationGuard _guard;
  StreamSubscription<LocationSnapshot>? _locationSubscription;
  LocationSnapshot? _snapshot;
  List<DriverJobView> _jobs = const [];
  DriverJobView? _selectedJob;
  bool _online = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _guard = LocationGuard(ref.read(apiClientProvider));
    _locationSubscription = _guard.stream.listen((snapshot) {
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
      if (snapshot.mocked && _online) {
        _setOfflineForMock();
      }
    });
    _loadJobs();
  }

  Future<void> _loadJobs() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final payload = await ref.read(apiClientProvider).get('/driver/jobs');
      final raw = List<dynamic>.from(payload['data'] as List? ?? const []);
      final parsed = raw.map(_parseJob).toList();
      if (!mounted) return;
      setState(() {
        _jobs = parsed;
        if (_selectedJob == null && parsed.isNotEmpty) {
          _selectedJob = parsed.firstWhere(
            (job) => !job.isCompleted,
            orElse: () => parsed.first,
          );
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  DriverJobView _parseJob(dynamic raw) {
    final job = Map<String, dynamic>.from(raw as Map);

    double? number(List<String> keys) {
      for (final key in keys) {
        final value = job[key];
        if (value is num) return value.toDouble();
        final parsed = double.tryParse(value.toString());
        if (parsed != null) return parsed;
      }
      return null;
    }

    LatLng? point(List<String> latKeys, List<String> lngKeys) {
      final lat = number(latKeys);
      final lng = number(lngKeys);
      if (lat == null || lng == null) return null;
      if (lat.abs() > 90 || lng.abs() > 180) return null;
      return LatLng(lat, lng);
    }

    num? money = job['driver_fee'] is num
        ? job['driver_fee'] as num
        : job['shipping_fee'] is num
            ? job['shipping_fee'] as num
            : null;

    return DriverJobView(
      id: (job['id'] ?? job['job_id'] ?? '').toString(),
      code: (job['order_code'] ?? job['code'] ?? job['order_number'] ?? 'Order').toString(),
      status: (job['status'] ?? job['state'] ?? 'Menunggu').toString(),
      storeName: (job['store_name'] ?? job['merchant_name'] ?? 'Merchant').toString(),
      customerName: (job['customer_name'] ?? job['buyer_name'] ?? 'Pelanggan').toString(),
      pickupAddress: (job['pickup_address'] ?? job['store_address'] ?? job['origin_address'] ?? '-').toString(),
      dropoffAddress: (job['dropoff_address'] ?? job['customer_address'] ?? job['destination_address'] ?? '-').toString(),
      price: money,
      pickup: point(
        const ['pickup_lat', 'pickup_latitude', 'origin_lat', 'merchant_lat'],
        const ['pickup_lng', 'pickup_longitude', 'origin_lng', 'merchant_lng'],
      ),
      dropoff: point(
        const ['dropoff_lat', 'dropoff_latitude', 'destination_lat', 'customer_lat'],
        const ['dropoff_lng', 'dropoff_longitude', 'destination_lng', 'customer_lng'],
      ),
    );
  }

  Future<void> _setOnline(bool value) async {
    if (!value) {
      await _guard.stop();
      if (mounted) setState(() => _online = false);
      return;
    }

    try {
      await _guard.start();
      if (!mounted) return;
      setState(() => _online = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Anda sekarang online. Lokasi mulai dipantau.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _setOfflineForMock() async {
    await _guard.stop();
    if (!mounted) return;
    setState(() => _online = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFFD32F2F),
        content: Text('Mock location terdeteksi. Anda otomatis offline.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DriverHome(
        online: _online,
        jobs: _jobs,
        loading: _loading,
        error: _error,
        snapshot: _snapshot,
        onOnlineChanged: _setOnline,
        onRefresh: _loadJobs,
        onOpenJob: (job) {
          setState(() {
            _selectedJob = job;
            _index = 2;
          });
        },
      ),
      DriverOrders(
        jobs: _jobs,
        selectedJob: _selectedJob,
        onSelect: (job) {
          setState(() {
            _selectedJob = job;
            _index = 2;
          });
        },
        onRefresh: _loadJobs,
      ),
      DriverMapPage(snapshot: _snapshot, job: _selectedJob),
      DriverHistory(jobs: _jobs),
      const DriverProfile(),
    ];

    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Beranda',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_shipping_outlined),
            selectedIcon: Icon(Icons.local_shipping),
            label: 'Order',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Peta',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'Riwayat',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Akun',
          ),
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

class DriverHome extends StatelessWidget {
  const DriverHome({
    super.key,
    required this.online,
    required this.jobs,
    required this.loading,
    required this.error,
    required this.snapshot,
    required this.onOnlineChanged,
    required this.onRefresh,
    required this.onOpenJob,
  });

  final bool online;
  final List<DriverJobView> jobs;
  final bool loading;
  final String? error;
  final LocationSnapshot? snapshot;
  final ValueChanged<bool> onOnlineChanged;
  final Future<void> Function() onRefresh;
  final ValueChanged<DriverJobView> onOpenJob;

  @override
  Widget build(BuildContext context) {
    final fresh = jobs.where((job) => job.isNew).toList();
    final active = jobs.where((job) => job.isActive).toList();
    final earnings = jobs.fold<num>(0, (sum, job) => sum + (job.price ?? 0));

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 52, 16, 110),
        children: [
          Row(
            children: [
              Image.asset(
                'assets/branding/bersolek-mart-icon-512.png',
                width: 42,
                height: 42,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BersolekDriver',
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      'Driver lokal BersolekMart',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
              _OnlinePill(value: online, onChanged: onOnlineChanged),
            ],
          ),
          const SizedBox(height: 18),
          _HeroCard(online: online, snapshot: snapshot),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.receipt_long_outlined,
                  label: 'Order',
                  value: jobs.length.toString(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Pendapatan',
                  value: _rupiah(earnings),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Pesanan baru',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              TextButton(
                onPressed: fresh.isEmpty ? null : () => onOpenJob(fresh.first),
                child: const Text('Lihat semua'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (error != null)
            _ErrorCard(message: error!, onRetry: onRefresh)
          else if (fresh.isEmpty)
            _EmptyCard(
              icon: online ? Icons.check_circle_outline : Icons.power_settings_new,
              title: online ? 'Belum ada order baru' : 'Aktifkan status Online',
              subtitle: online
                  ? 'Order dari server akan muncul di area ini.'
                  : 'Saat online, driver siap menerima penugasan.',
            )
          else
            _OrderCard(
              job: fresh.first,
              buttonText: 'Lihat Order',
              onPressed: () => onOpenJob(fresh.first),
            ),
          const SizedBox(height: 22),
          const Text(
            'Sedang berjalan',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          if (active.isEmpty)
            const _EmptyCard(
              icon: Icons.route_outlined,
              title: 'Belum ada pengantaran aktif',
              subtitle: 'Order aktif akan tampil di sini.',
            )
          else
            ...active.take(2).map(
              (job) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _OrderCard(
                  job: job,
                  buttonText: 'Buka Peta',
                  onPressed: () => onOpenJob(job),
                ),
              ),
            ),
          const SizedBox(height: 12),
          _SecurityCard(snapshot: snapshot, online: online),
        ],
      ),
    );
  }
}

class DriverOrders extends StatelessWidget {
  const DriverOrders({
    super.key,
    required this.jobs,
    required this.selectedJob,
    required this.onSelect,
    required this.onRefresh,
  });

  final List<DriverJobView> jobs;
  final DriverJobView? selectedJob;
  final ValueChanged<DriverJobView> onSelect;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final fresh = jobs.where((job) => job.isNew).toList();
    final active = jobs.where((job) => job.isActive).toList();
    final completed = jobs.where((job) => job.isCompleted).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                ${fresh.length} baru • ${active.length} aktif,
                style: const TextStyle(color: Colors.black54),
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: onRefresh,
        child: DefaultTabController(
          length: 3,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: 'Baru'),
                  Tab(text: 'Aktif'),
                  Tab(text: 'Selesai'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _JobList(
                      jobs: fresh,
                      selectedJob: selectedJob,
                      onSelect: onSelect,
                      emptyTitle: 'Belum ada order baru',
                    ),
                    _JobList(
                      jobs: active,
                      selectedJob: selectedJob,
                      onSelect: onSelect,
                      emptyTitle: 'Belum ada pengantaran aktif',
                    ),
                    _JobList(
                      jobs: completed,
                      selectedJob: selectedJob,
                      onSelect: onSelect,
                      emptyTitle: 'Belum ada riwayat',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DriverMapPage extends StatefulWidget {
  const DriverMapPage({
    super.key,
    required this.snapshot,
    required this.job,
  });

  final LocationSnapshot? snapshot;
  final DriverJobView? job;

  @override
  State<DriverMapPage> createState() => _DriverMapPageState();
}

class _DriverMapPageState extends State<DriverMapPage> {
  final MapController _mapController = MapController();

  static const LatLng _fallback = LatLng(-7.7543, 113.2159);

  LatLng get _driverPoint {
    final position = widget.snapshot?.position;
    return position == null
        ? _fallback
        : LatLng(position.latitude, position.longitude);
  }

  List<LatLng> get _route {
    final points = <LatLng>[_driverPoint];
    if (widget.job?.pickup != null) points.add(widget.job!.pickup!);
    if (widget.job?.dropoff != null) points.add(widget.job!.dropoff!);
    return points.length > 1 ? points : const [];
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _driverPoint,
            initialZoom: 15,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.bersolekmart.mobile',
            ),
            if (route.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: route,
                    strokeWidth: 5,
                    color: const Color(0xFF16A56A),
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                Marker(
                  point: _driverPoint,
                  width: 50,
                  height: 50,
                  child: const _MapMarker(
                    icon: Icons.navigation_rounded,
                    color: Color(0xFF147D58),
                  ),
                ),
                if (widget.job?.pickup != null)
                  Marker(
                    point: widget.job!.pickup!,
                    width: 44,
                    height: 44,
                    child: const _MapMarker(
                      icon: Icons.storefront_rounded,
                      color: Color(0xFF147D58),
                    ),
                  ),
                if (widget.job?.dropoff != null)
                  Marker(
                    point: widget.job!.dropoff!,
                    width: 44,
                    height: 44,
                    child: const _MapMarker(
                      icon: Icons.location_on_rounded,
                      color: Color(0xFFD84040),
                    ),
                  ),
              ],
            ),
            RichAttributionWidget(
              attributions: [
                TextSourceAttribution('OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                _MapChip(
                  icon: Icons.my_location_rounded,
                  label: 'Lokasi saya',
                ),
                const Spacer(),
                Material(
                  color: Colors.white,
                  elevation: 6,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _mapController.move(_driverPoint, 16),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.gps_fixed_rounded),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 92),
              child: _MapSheet(
                job: widget.job,
                gpsReady: widget.snapshot != null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class DriverHistory extends StatelessWidget {
  const DriverHistory({super.key, required this.jobs});

  final List<DriverJobView> jobs;

  @override
  Widget build(BuildContext context) {
    final completed = jobs.where((job) => job.isCompleted).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat')),
      body: completed.isEmpty
          ? const _EmptyCard(
              icon: Icons.history_outlined,
              title: 'Belum ada riwayat',
              subtitle: 'Pengantaran yang selesai akan tercatat di sini.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
              itemCount: completed.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _OrderCard(
                job: completed[index],
                buttonText: 'Selesai',
              ),
            ),
    );
  }
}

class DriverProfile extends ConsumerWidget {
  const DriverProfile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final user = session?.user ?? const <String, dynamic>{};

    return Scaffold(
      appBar: AppBar(title: const Text('Akun')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 110),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    child: Text(
                      (user['full_name'] ?? 'D')
                          .toString()
                          .substring(0, 1)
                          .toUpperCase(),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user['full_name']?.toString() ?? '-',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Driver BersolekMart',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const _AccountTile(
            icon: Icons.shield_outlined,
            title: 'Keamanan lokasi',
            subtitle: 'Deteksi mock location dan anomali pergerakan aktif',
          ),
          const _AccountTile(
            icon: Icons.map_outlined,
            title: 'Peta',
            subtitle: 'OpenStreetMap dengan lokasi perangkat',
          ),
          const _AccountTile(
            icon: Icons.support_agent_outlined,
            title: 'Bantuan Driver',
            subtitle: 'Panduan order, pickup, dan pengantaran',
          ),
          const SizedBox(height: 14),
          FilledButton.tonalIcon(
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
            label: const Text('Keluar'),
          ),
        ],
      ),
    );
  }
}

class _OnlinePill extends StatelessWidget {
  const _OnlinePill({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: value ? const Color(0xFFDDF6E9) : const Color(0xFFE8ECEB),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: const Color(0xFF16A56A),
            activeThumbColor: Colors.white,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 9),
            child: Text(
              value ? 'Online' : 'Offline',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: value ? const Color(0xFF147D58) : Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.online, required this.snapshot});

  final bool online;
  final LocationSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final mocked = snapshot?.mocked ?? false;
    final title = mocked
        ? 'Lokasi mencurigakan'
        : online
            ? 'Anda sedang online'
            : 'Anda sedang offline';

    final subtitle = mocked
        ? 'Sinkronisasi dihentikan sampai lokasi valid.'
        : snapshot == null
            ? 'Aktifkan Online untuk mulai memantau lokasi.'
            : 'GPS aktif. Akurasi ${snapshot!.position.accuracy.toStringAsFixed(0)} m.';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0E6D50), Color(0xFF1BB27A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(36),
              shape: BoxShape.circle,
            ),
            child: Icon(
              mocked ? Icons.location_off_rounded : Icons.two_wheeler_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFF147D58)),
            const SizedBox(height: 12),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.job,
    required this.buttonText,
    this.onPressed,
  });

  final DriverJobView job;
  final String buttonText;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    job.code,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                ),
                _StatusChip(status: job.status),
              ],
            ),
            const SizedBox(height: 14),
            _RouteLine(
              icon: Icons.storefront_rounded,
              color: const Color(0xFF147D58),
              title: job.storeName,
              address: job.pickupAddress,
            ),
            const SizedBox(height: 10),
            _RouteLine(
              icon: Icons.location_on_rounded,
              color: const Color(0xFFD84040),
              title: job.customerName,
              address: job.dropoffAddress,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _rupiah(job.price),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: onPressed,
                  child: Text(buttonText),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final value = status.toLowerCase();
    final green = value.contains('selesai') || value.contains('complete');
    final blue = value.contains('antar') || value.contains('deliver');
    final orange = value.contains('pickup') || value.contains('ambil');

    final background = green
        ? const Color(0xFFDDF6E9)
        : blue
            ? const Color(0xFFE2EEFF)
            : orange
                ? const Color(0xFFFFF0D5)
                : const Color(0xFFFFE5E5);

    final foreground = green
        ? const Color(0xFF147D58)
        : blue
            ? const Color(0xFF235EAA)
            : orange
                ? const Color(0xFF9B5B00)
                : const Color(0xFFB72A2A);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _JobList extends StatelessWidget {
  const _JobList({
    required this.jobs,
    required this.selectedJob,
    required this.onSelect,
    required this.emptyTitle,
  });

  final List<DriverJobView> jobs;
  final DriverJobView? selectedJob;
  final ValueChanged<DriverJobView> onSelect;
  final String emptyTitle;

  @override
  Widget build(BuildContext context) {
    if (jobs.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 30, 16, 110),
        children: [
          _EmptyCard(
            icon: Icons.inbox_outlined,
            title: emptyTitle,
            subtitle: 'Daftar akan muncul setelah server mengirim data.',
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
      itemCount: jobs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final job = jobs[index];
        final selected = selectedJob?.id == job.id;
        return Container(
          decoration: BoxDecoration(
            border: selected
                ? Border.all(
                    color: const Color(0xFF16A56A),
                    width: 1.5,
                  )
                : null,
            borderRadius: BorderRadius.circular(18),
          ),
          child: _OrderCard(
            job: job,
            buttonText: selected ? 'Dipilih' : 'Lihat Peta',
            onPressed: () => onSelect(job),
          ),
        );
      },
    );
  }
}

class _RouteLine extends StatelessWidget {
  const _RouteLine({
    required this.icon,
    required this.color,
    required this.title,
    required this.address,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String address;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                address,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MapSheet extends StatelessWidget {
  const _MapSheet({required this.job, required this.gpsReady});

  final DriverJobView? job;
  final bool gpsReady;

  @override
  Widget build(BuildContext context) {
    if (job == null) {
      return Card(
        elevation: 10,
        child: const Padding(
          padding: EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Color(0xFFDDF6E9),
                child: Icon(Icons.map_outlined, color: Color(0xFF147D58)),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Pilih order untuk melihat titik pickup dan tujuan.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 10,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    job!.code,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _StatusChip(status: job!.status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              gpsReady ? 'GPS aktif' : 'Menunggu GPS',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            _RouteLine(
              icon: Icons.storefront_rounded,
              color: const Color(0xFF147D58),
              title: job!.storeName,
              address: job!.pickupAddress,
            ),
            const SizedBox(height: 8),
            _RouteLine(
              icon: Icons.location_on_rounded,
              color: const Color(0xFFD84040),
              title: job!.customerName,
              address: job!.dropoffAddress,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: null,
                icon: const Icon(Icons.navigation_rounded),
                label: const Text('Navigasi jalan'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapChip extends StatelessWidget {
  const _MapChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            blurRadius: 12,
            color: Color(0x22000000),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: const Color(0xFF147D58)),
            const SizedBox(width: 7),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _MapMarker extends StatelessWidget {
  const _MapMarker({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            blurRadius: 10,
            color: Color(0x33000000),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 23),
        ),
      ),
    );
  }
}

class _SecurityCard extends StatelessWidget {
  const _SecurityCard({required this.snapshot, required this.online});

  final LocationSnapshot? snapshot;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final mocked = snapshot?.mocked ?? false;
    final anomaly = snapshot?.movementAnomaly ?? false;

    final title = mocked
        ? 'Peringatan lokasi'
        : anomaly
            ? 'Pergerakan perlu diverifikasi'
            : online
                ? 'Lokasi sedang dipantau'
                : 'Lokasi belum aktif';

    final subtitle = mocked
        ? 'Mock location terdeteksi dan sinkronisasi dihentikan.'
        : anomaly
            ? 'Perpindahan lokasi melebihi ambang kewajaran.'
            : online
                ? 'Lokasi valid dikirim ke server secara berkala.'
                : 'Aktifkan Online untuk memulai pemantauan.';

    final icon = mocked
        ? Icons.location_off_rounded
        : anomaly
            ? Icons.warning_amber_rounded
            : Icons.shield_outlined;

    final color = mocked
        ? const Color(0xFFD32F2F)
        : anomaly
            ? const Color(0xFF9B5B00)
            : const Color(0xFF147D58);

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withAlpha(24),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF147D58)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFFF2F2),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: Color(0xFFD32F2F),
              size: 34,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF147D58), size: 40),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

String _rupiah(num? value) {
  if (value == null) return 'Rp -';
  final text = value.round().toString();
  final groups = <String>[];
  var end = text.length;

  while (end > 0) {
    final start = end - 3 < 0 ? 0 : end - 3;
    groups.insert(0, text.substring(start, end));
    end = start;
  }

  return 'Rp ${groups.join('.')}';
}
