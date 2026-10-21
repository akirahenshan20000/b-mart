import 'dart:async';

import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/location/location_guard.dart';
import '../../core/network/api_client.dart';
import '../account/account_profile_edit_page.dart';
import '../account/member_data_pages.dart';
import 'driver_base_location_page.dart';
import '../../shared/widgets/brand_bottom_navigation.dart';

/// Converts structured API fields to human-readable text for driver screens.
String readableDriverValue(dynamic value, {String fallback = '-'}) {
  if (value == null) return fallback;
  if (value is Map) {
    for (final key in const [
      'address_line', 'full_address', 'formatted_address', 'address',
      'label', 'name', 'full_name', 'recipient_name', 'title',
      'status_label', 'status_name', 'status', 'value', 'text',
      'phone', 'email',
    ]) {
      final candidate = value[key];
      if (candidate != null && candidate is! Map && candidate is! List) {
        final text = candidate.toString().trim();
        if (text.isNotEmpty) return text;
      }
    }
    return fallback;
  }
  if (value is List) {
    final parts = value
        .map((item) => readableDriverValue(item, fallback: ''))
        .where((item) => item.isNotEmpty)
        .toList();
    return parts.isEmpty ? fallback : parts.join(', ');
  }
  final text = value.toString().trim();
  if (text.isEmpty) return fallback;
  if ((text.startsWith('{') && text.endsWith('}')) ||
      (text.startsWith('[') && text.endsWith(']'))) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map || decoded is List) {
        return readableDriverValue(decoded, fallback: fallback);
      }
    } catch (_) {
      return fallback;
    }
  }
  return text;
}

/// Road leg that matches the existing PWA/PHP delivery state machine.
/// null means the driver should not be navigating to a road destination at this stage.
String? driverNavigationLegForStatus(String status) {
  switch (status.trim().toLowerCase()) {
    case 'assigned':
    case 'accepted':
    case 'picking_up':
      return 'pickup';
    case 'picked_up':
    case 'delivering':
      return 'dropoff';
    default:
      return null;
  }
}

class DriverJobView {
  const DriverJobView({
    required this.id,
    required this.code,
    required this.status,
    this.availableToAccept = false,
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
  final bool availableToAccept;
  final String storeName;
  final String customerName;
  final String pickupAddress;
  final String dropoffAddress;
  final num? price;
  final LatLng? pickup;
  final LatLng? dropoff;

  bool get isCompleted {
    final value = status.toLowerCase();
    return value == 'completed' || value.contains('selesai');
  }

  bool get isActive {
    final value = status.toLowerCase();
    if (isCompleted || isNew) return false;
    return value == 'assigned' ||
        value == 'accepted' ||
        value == 'picking_up' ||
        value == 'picked_up' ||
        value == 'delivering' ||
        value == 'arrived' ||
        value == 'delivered' ||
        value.contains('aktif') ||
        value.contains('antar');
  }

  bool get isNew {
    final value = status.toLowerCase();
    if (isCompleted) return false;
    return value == 'available' || (value == 'assigned' && availableToAccept);
  }

  String get statusLabel {
    switch (status.toLowerCase()) {
      case 'available':
        return 'Tersedia';
      case 'assigned':
        return 'Ditugaskan';
      case 'accepted':
        return 'Diterima';
      case 'picking_up':
        return 'Menuju Pickup';
      case 'picked_up':
        return 'Pesanan Diambil';
      case 'delivering':
        return 'Dalam Pengantaran';
      case 'arrived':
        return 'Sampai Tujuan';
      case 'delivered':
        return 'Bukti Pengantaran';
      case 'completed':
        return 'Selesai';
      default:
        return readableDriverValue(status, fallback: 'Menunggu');
    }
  }

  DriverJobView withStatus(String nextStatus) => DriverJobView(
    id: id,
    code: code,
    status: nextStatus,
    availableToAccept: nextStatus == 'available' || nextStatus == 'assigned'
        ? availableToAccept
        : false,
    storeName: storeName,
    customerName: customerName,
    pickupAddress: pickupAddress,
    dropoffAddress: dropoffAddress,
    price: price,
    pickup: pickup,
    dropoff: dropoff,
  );
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
  bool _mapFullscreen = false;
  Timer? _jobPoller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _guard = LocationGuard(ref.read(apiClientProvider));
    _locationSubscription = _guard.stream.listen((snapshot) {
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
      if (snapshot.mocked && _online && !kDebugMode) {
        _setOfflineForMock();
      }
    });
    _loadJobs();
    unawaited(_restoreAvailability());
    _jobPoller = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && _online) _loadJobs(silent: true);
    });
  }

  Future<void> _restoreAvailability() async {
    var serverStatus = '';
    try {
      final payload = await ref.read(apiClientProvider).get('/driver/profile');
      final profile = payload['data'];
      serverStatus = profile is Map ? (profile['status'] ?? '').toString().toLowerCase() : '';
      if (!['available', 'assigned', 'delivering'].contains(serverStatus)) return;
      await _guard.start();
      if (mounted) setState(() => _online = true);
    } catch (_) {
      // A driver with no active task must not remain available without GPS.
      if (serverStatus == 'available') {
        try {
          await ref.read(apiClientProvider).post('/driver/status', {'status': 'offline'});
        } catch (_) {
          // Keep the failure visible; do not claim server availability changed.
        }
      }
      if (!mounted) return;
      setState(() {
        _online = false;
        _error = 'Status dan GPS driver belum tersambung. Periksa izin lokasi, lalu aktifkan Online kembali.';
      });
    }
  }

  Future<void> _loadJobs({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final payload = await ref.read(apiClientProvider).get('/driver/jobs');
      final raw = List<dynamic>.from(payload['data'] as List? ?? const []);
      final parsed = raw.map(_parseJob).toList();
      if (!mounted) return;
      setState(() {
        _jobs = parsed;
        final selectedId = _selectedJob?.id;
        if (selectedId != null) {
          for (final job in parsed) {
            if (job.id == selectedId) {
              _selectedJob = job;
              break;
            }
          }
        }
        if (_selectedJob == null && parsed.isNotEmpty) {
          _selectedJob = parsed.firstWhere(
            (job) => !job.isCompleted,
            orElse: () => parsed.first,
          );
        }
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Pesanan gagal dimuat. Periksa koneksi lalu coba lagi.';
      });
    }
  }

  DriverJobView _parseJob(dynamic raw) {
    final job = Map<String, dynamic>.from(raw as Map);
    Map<String, dynamic> objectValue(dynamic value) {
      if (value is Map) return Map<String, dynamic>.from(value);
      if (value is String && value.trim().startsWith('{')) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is Map) return Map<String, dynamic>.from(decoded);
        } catch (_) {
          // Malformed optional address data must not break the order list.
        }
      }
      return <String, dynamic>{};
    }
    final dropoff = objectValue(job['dropoff_address']);

    double? number(List<String> keys) {
      for (final key in keys) {
        final value = job[key];
        if (value is num) return value.toDouble();
        final parsed = double.tryParse(value.toString());
        if (parsed != null) return parsed;
      }
      return null;
    }

    LatLng? point(
      List<String> latKeys,
      List<String> lngKeys, {
      bool useDropoffAddress = false,
    }) {
      double? parseAddressCoordinate(dynamic value) {
        if (value is num) return value.toDouble();
        return double.tryParse(value?.toString() ?? '');
      }
      final addressLat = useDropoffAddress
          ? parseAddressCoordinate(dropoff['latitude'] ?? dropoff['lat'])
          : null;
      final addressLng = useDropoffAddress
          ? parseAddressCoordinate(dropoff['longitude'] ?? dropoff['lng'] ?? dropoff['lon'])
          : null;
      final lat = number(latKeys) ?? addressLat;
      final lng = number(lngKeys) ?? addressLng;
      if (lat == null || lng == null) return null;
      if (!lat.isFinite || !lng.isFinite || lat.abs() > 90 || lng.abs() > 180 || (lat == 0 && lng == 0)) return null;
      return LatLng(lat, lng);
    }

    final money = number(const ['driver_fee', 'fee', 'shipping_fee']);

    return DriverJobView(
      id: (job['id'] ?? job['job_id'] ?? '').toString(),
      code: (job['order_code'] ?? job['code'] ?? job['order_number'] ?? 'Order').toString(),
      status: readableDriverValue(job['status'] ?? job['state'], fallback: 'Menunggu'),
      availableToAccept: job['available_to_accept'] == true ||
          job['available_to_accept']?.toString() == '1',
      storeName: readableDriverValue(job['store_name'] ?? job['merchant_name'], fallback: 'Merchant'),
      customerName: readableDriverValue(job['customer_name'] ?? job['buyer_name'] ?? dropoff['recipient_name'], fallback: 'Pelanggan'),
      pickupAddress: readableDriverValue(job['pickup_address'] ?? job['store_address'] ?? job['origin_address']),
      dropoffAddress: readableDriverValue(job['dropoff_address'] ?? job['customer_address'] ?? job['destination_address']),
      price: money,
      pickup: point(
        const ['pickup_lat', 'pickup_latitude', 'origin_lat', 'merchant_lat'],
        const ['pickup_lng', 'pickup_longitude', 'origin_lng', 'merchant_lng'],
      ),
      dropoff: point(
        const ['dropoff_lat', 'dropoff_latitude', 'destination_lat', 'customer_lat'],
        const ['dropoff_lng', 'dropoff_longitude', 'destination_lng', 'customer_lng'],
        useDropoffAddress: true,
      ),
    );
  }

  void _openJobDetail(DriverJobView job) {
    setState(() => _selectedJob = job);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (detailContext) => DriverOrderDetailPage(
          job: job,
          snapshot: _snapshot,
          onOpenMap: () {
            Navigator.of(detailContext).pop();
            if (mounted) setState(() => _index = 2);
          },
          onStatusChanged: _loadJobs,
        ),
      ),
    );
  }

  Future<void> _setOnline(bool value) async {
    if (!value) {
      try {
        // Keep tracking active if the server rejects going offline during a job.
        await ref.read(apiClientProvider).post('/driver/status', {'status': 'offline'});
        await _guard.stop();
        if (!mounted) return;
        setState(() => _online = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Anda offline. Status server sudah diperbarui.')),
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF8A001D),
            content: Text('Tidak dapat offline saat tugas aktif atau server belum tersambung. GPS tetap berjalan.'),
          ),
        );
      }
      return;
    }

    try {
      // Request the GPS permission/stream first; the driver is only shown Online after
      // the existing web-equivalent availability rule is confirmed by the API.
      await _guard.start();
      try {
        await ref.read(apiClientProvider).post('/driver/status', {'status': 'available'});
      } catch (_) {
        await _guard.stop();
        rethrow;
      }
      if (!mounted) return;
      setState(() => _online = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Anda online. Status server aktif dan GPS mulai dipantau.')),
      );
    } catch (error) {
      await _guard.stop();
      if (!mounted) return;
      setState(() => _online = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF8A001D),
          content: Text('Belum dapat Online. Periksa izin GPS dan koneksi server, lalu coba lagi.'),
        ),
      );
    }
  }

  Future<void> _setOfflineForMock() async {
    await _guard.stop();
    var serverConfirmed = false;
    try {
      await ref.read(apiClientProvider).post('/driver/status', {'status': 'offline'});
      serverConfirmed = true;
    } catch (_) {
      if (kDebugMode) debugPrint('[BersolekMart Driver] server offline status could not be confirmed after mock GPS.');
    }
    if (!mounted) return;
    setState(() => _online = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFD32F2F),
        content: Text(serverConfirmed
            ? 'Mock location terdeteksi. GPS dihentikan dan status server menjadi offline.'
            : 'Mock location terdeteksi. GPS dihentikan; status server belum dapat dikonfirmasi.'),
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
        onOpenJob: _openJobDetail,
      ),
      DriverOrders(
        jobs: _jobs,
        selectedJob: _selectedJob,
        onSelect: _openJobDetail,
        onRefresh: _loadJobs,
      ),
      DriverMapPage(
        snapshot: _snapshot,
        job: _selectedJob,
        fullscreen: _mapFullscreen,
        onFullscreenChanged: (value) => setState(() => _mapFullscreen = value),
      ),
      DriverHistory(jobs: _jobs),
      DriverProfile(snapshot: _snapshot, onOpenMap: () => setState(() => _index = 2)),
    ];

    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: _mapFullscreen ? null : BrandBottomNavigation(
        dark: true,
        selectedIndex: _index,
        onSelected: (value) => setState(() {
          _mapFullscreen = false;
          _index = value;
        }),
        items: const [
          BrandNavItem('Beranda', Icons.home_outlined, Icons.home_rounded),
          BrandNavItem('Order', Icons.local_shipping_outlined, Icons.local_shipping_rounded),
          BrandNavItem('Peta', Icons.map_outlined, Icons.map_rounded),
          BrandNavItem('Riwayat', Icons.history_outlined, Icons.history_rounded),
          BrandNavItem('Akun', Icons.person_outline, Icons.person_rounded),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _jobPoller?.cancel();
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
    final completedCount = jobs.where((job) => job.isCompleted).length;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 20),
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFD20A2E),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.delivery_dining_rounded, color: Colors.white, size: 29),
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
          const SizedBox(height: 14),
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
                  icon: Icons.task_alt_rounded,
                  label: 'Order selesai',
                  value: completedCount.toString(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
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
                  buttonText: 'Detail Order',
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
                '${fresh.length} baru • ${active.length} aktif',
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

class DriverOrderDetailPage extends ConsumerStatefulWidget {
  const DriverOrderDetailPage({
    super.key,
    required this.job,
    required this.snapshot,
    required this.onOpenMap,
    required this.onStatusChanged,
  });

  final DriverJobView job;
  final LocationSnapshot? snapshot;
  final VoidCallback onOpenMap;
  final Future<void> Function() onStatusChanged;

  @override
  ConsumerState<DriverOrderDetailPage> createState() => _DriverOrderDetailPageState();
}

class _DriverOrderDetailPageState extends ConsumerState<DriverOrderDetailPage> {
  late DriverJobView _job;
  bool _busy = false;
  String? _error;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _job = widget.job;
  }

  String? get _nextStatus {
    switch (_job.status.toLowerCase()) {
      case 'available':
      case 'assigned':
        return 'accepted';
      case 'accepted':
        return 'picking_up';
      case 'picking_up':
        return 'picked_up';
      case 'picked_up':
        return 'delivering';
      case 'delivering':
        return 'arrived';
      case 'arrived':
        return 'delivered';
      case 'delivered':
        return 'completed';
      default:
        return null;
    }
  }

  String get _nextActionLabel {
    switch (_nextStatus) {
      case 'accepted': return 'Terima Order';
      case 'picking_up': return 'Mulai menuju merchant';
      case 'picked_up': return 'Konfirmasi pesanan diambil';
      case 'delivering': return 'Mulai pengantaran';
      case 'arrived': return 'Ambil foto bukti & tiba di tujuan';
      case 'delivered': return 'Konfirmasi serah terima';
      case 'completed': return 'Selesaikan Order';
      default: return 'Order selesai';
    }
  }

  int get _stage {
    switch (_job.status.toLowerCase()) {
      case 'available': return 0;
      case 'assigned': return _job.availableToAccept ? 0 : 1;
      case 'accepted': return 1;
      case 'picking_up':
      case 'picked_up': return 2;
      case 'delivering': return 3;
      case 'arrived':
      case 'delivered': return 4;
      case 'completed': return 5;
      default: return 0;
    }
  }

  Future<ImageSource?> _chooseProofSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Foto bukti pengantaran',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text('Foto dikirim ke backend dan menjadi bagian dari catatan pengantaran.',
                style: TextStyle(color: Colors.black54, height: 1.4)),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Ambil foto dengan kamera'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Pilih dari galeri'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _advanceStatus() async {
    final requestedStatus = _nextStatus;
    final jobId = int.tryParse(_job.id);
    if (requestedStatus == null || jobId == null || jobId < 1) return;

    XFile? proof;
    if (requestedStatus == 'arrived') {
      try {
        final source = await _chooseProofSource();
        if (source == null || !mounted) return;
        proof = await _imagePicker.pickImage(
          source: source,
          imageQuality: 82,
          maxWidth: 1800,
        );
        if (proof == null) return;
      } catch (error) {
        if (mounted) setState(() => _error = 'Kamera/galeri tidak dapat dibuka. Periksa izin perangkat lalu coba lagi.');
        return;
      }
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final fields = <String, String>{'status': requestedStatus};
      final location = widget.snapshot;
      if (location != null && !location.mocked) {
        fields['lat'] = location.position.latitude.toString();
        fields['lng'] = location.position.longitude.toString();
        fields['accuracy'] = location.position.accuracy.toString();
        fields['mock_location'] = '0';
      }

      final payload = proof == null
          ? await ref.read(apiClientProvider).post('/driver/jobs/$jobId/status', fields)
          : await ref.read(apiClientProvider).postMultipart(
              '/driver/jobs/$jobId/status',
              fields: fields,
              filePath: proof.path,
              fileField: 'proof_photo',
            );

      if (payload is! Map || payload['data'] is! Map) {
        throw const FormatException('Respons perubahan status dari server tidak sesuai kontrak.');
      }
      final data = Map<String, dynamic>.from(payload['data'] as Map);
      final rawJob = data['job'] is Map ? Map<String, dynamic>.from(data['job'] as Map) : <String, dynamic>{};
      final actualStatus = (data['status'] ?? rawJob['status'] ?? '').toString().trim();
      if (actualStatus.isEmpty) {
        throw const FormatException('Server tidak mengembalikan status order terbaru.');
      }
      if (!mounted) return;
      setState(() => _job = _job.withStatus(actualStatus));
      await widget.onStatusChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Status order diperbarui oleh server: ${_job.statusLabel}.')),
      );
      if (const ['picking_up', 'delivering'].contains(actualStatus.toLowerCase())) {
        // Status has already been accepted by the API; now open the same in-app live map.
        await Future<void>.delayed(const Duration(milliseconds: 180));
        if (mounted) widget.onOpenMap();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error is ApiException
          ? apiErrorMessage(error)
          : error is FormatException
              ? error.message
              : 'Status order gagal diperbarui. Periksa koneksi dan status terbaru di server.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nextStatus = _nextStatus;
    final towardCustomer = const ['picked_up', 'delivering', 'arrived', 'delivered'].contains(_job.status.toLowerCase());
    final destinationLabel = towardCustomer ? 'Tujuan pelanggan' : 'Titik pickup merchant';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF171113),
        elevation: 0,
        title: const Text('Detail Order', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF25191C), Color(0xFF111111)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(child: Text('ORDER PENGANTARAN',
                              style: TextStyle(color: Colors.white70, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.w900))),
                            _StatusChip(status: _job.statusLabel),
                          ],
                        ),
                        const SizedBox(height: 9),
                        Text(_job.code, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 8),
                        Text(_job.statusLabel, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(_job.price == null ? 'Biaya pengantaran menunggu data server' : 'Biaya pengantaran ${_rupiah(_job.price)}',
                          style: const TextStyle(color: Colors.white70, height: 1.35)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _DriverDetailSection(
                    title: 'Proses pengantaran',
                    icon: Icons.route_outlined,
                    child: _DriverProgressBar(
                      current: _stage,
                      status: _job.statusLabel,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DriverDetailSection(
                    title: 'Rute order',
                    icon: Icons.location_on_outlined,
                    child: Column(
                      children: [
                        _DriverAddressRow(
                          title: _job.storeName,
                          address: _job.pickupAddress,
                          icon: Icons.storefront_rounded,
                          tint: const Color(0xFF147D58),
                        ),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 9, 0, 9),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Icon(Icons.more_vert_rounded, color: Color(0xFFB5A8AC), size: 20),
                          ),
                        ),
                        _DriverAddressRow(
                          title: _job.customerName,
                          address: _job.dropoffAddress,
                          icon: Icons.location_on_rounded,
                          tint: const Color(0xFFD20A2E),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.navigation_outlined, color: Color(0xFFD20A2E), size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text(
                              'Tujuan berikutnya: $destinationLabel',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                            )),
                            TextButton(onPressed: widget.onOpenMap, child: const Text('Lihat peta')),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE9EA),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0x22D20A2E)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Color(0xFFB00020)),
                          const SizedBox(width: 9),
                          Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFF8F0019), height: 1.4))),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Color(0x10000000), blurRadius: 16, offset: Offset(0, -4))],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy || nextStatus == null ? null : _advanceStatus,
                      icon: _busy
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Icon(const ['arrived', 'delivered', 'completed'].contains(nextStatus)
                              ? Icons.photo_camera_outlined
                              : Icons.check_circle_outline_rounded),
                      label: Text(_busy ? 'Mengirim ke server…' : _nextActionLabel),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : widget.onOpenMap,
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Lihat peta order'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DriverDetailSection extends StatelessWidget {
  const _DriverDetailSection({required this.title, required this.icon, required this.child});
  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFEAE5E6)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, color: const Color(0xFFD20A2E), size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900))),
        ]),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

class _DriverAddressRow extends StatelessWidget {
  const _DriverAddressRow({required this.title, required this.address, required this.icon, required this.tint});
  final String title;
  final String address;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(color: tint.withAlpha(22), borderRadius: BorderRadius.circular(13)),
        child: Icon(icon, color: tint),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(address == '-' ? 'Alamat belum tersedia pada data order.' : address,
          style: const TextStyle(color: Colors.black54, height: 1.4)),
      ])),
    ],
  );
}

class _DriverProgressBar extends StatelessWidget {
  const _DriverProgressBar({required this.current, required this.status});
  final int current;
  final String status;

  static const _labels = [
    'Order',
    'Terima',
    'Pickup',
    'Antar',
    'Bukti',
    'Selesai',
  ];

  @override
  Widget build(BuildContext context) {
    final safeCurrent = current.clamp(0, _labels.length - 1).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List<Widget>.generate(_labels.length, (index) {
            final complete = index < safeCurrent;
            final active = index == safeCurrent;
            final fill = complete || active
                ? const Color(0xFFD20A2E)
                : const Color(0xFFE8DFE1);
            return Expanded(
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: complete ? const Color(0xFFD20A2E) : Colors.white,
                      border: Border.all(color: fill, width: 1.5),
                    ),
                    child: Icon(
                      complete ? Icons.check_rounded : active ? Icons.circle_rounded : Icons.circle_outlined,
                      size: complete ? 14 : 10,
                      color: complete ? Colors.white : fill,
                    ),
                  ),
                  if (index < _labels.length - 1)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: index < safeCurrent ? const Color(0xFFD20A2E) : const Color(0xFFE8DFE1),
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        Text(status, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        const SizedBox(height: 4),
        Text(
          'Tahap ${safeCurrent + 1} dari ${_labels.length} · Status terakhir dikonfirmasi backend.',
          style: const TextStyle(color: Colors.black54, fontSize: 12, height: 1.35),
        ),
        const SizedBox(height: 7),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: _labels.map((label) => Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: label == _labels[safeCurrent] ? FontWeight.w900 : FontWeight.w500,
              color: label == _labels[safeCurrent] ? const Color(0xFFD20A2E) : const Color(0xFF8A7D82),
            ),
          )).toList(),
        ),
      ],
    );
  }
}

class DriverMapPage extends StatefulWidget {
  const DriverMapPage({
    super.key,
    required this.snapshot,
    required this.job,
    this.fullscreen = false,
    this.onFullscreenChanged,
  });

  final LocationSnapshot? snapshot;
  final DriverJobView? job;
  final bool fullscreen;
  final ValueChanged<bool>? onFullscreenChanged;

  @override
  State<DriverMapPage> createState() => _DriverMapPageState();
}

class _DriverMapPageState extends State<DriverMapPage> {
  final MapController _mapController = MapController();
  bool _mapReady = false;
  bool _followGps = true;
  double _cameraZoom = 15;
  bool _routeLoading = false;
  String? _routeError;
  List<LatLng> _routePoints = const [];
  double? _routeDistanceMeters;
  double? _routeDurationSeconds;
  LatLng? _lastRouteOrigin;
  LatLng? _lastRouteDestination;
  DateTime? _lastRouteRequestAt;
  int _routeRequestGeneration = 0;

  bool get _hasUsableGps => widget.snapshot != null &&
      (!widget.snapshot!.mocked || kDebugMode);

  bool get _previewOnly => !_hasUsableGps && widget.job != null &&
      !widget.job!.isCompleted && widget.job?.pickup != null && widget.job?.dropoff != null;

  LatLng? get _routeDestination => _previewOnly ? widget.job?.dropoff : _activeDestination;

  LatLng? get _driverPoint {
    final snapshot = widget.snapshot;
    final position = snapshot?.position;
    if (position != null && _hasUsableGps) {
      return LatLng(position.latitude, position.longitude);
    }
    // Job coordinates are server-sourced. If neither GPS nor order coordinates
    // exist, render a GPS-waiting state instead of inventing a city coordinate.
    return widget.job?.pickup ?? widget.job?.dropoff;
  }

  LatLng? get _activeDestination {
    final job = widget.job;
    if (job == null || job.isCompleted) return null;
    switch (driverNavigationLegForStatus(job.status)) {
      case 'pickup':
        return job.pickup;
      case 'dropoff':
        return job.dropoff;
      default:
        // No route before assignment or after arrival/delivery/completion.
        return null;
    }
  }

  String get _destinationLabel =>
      driverNavigationLegForStatus(widget.job?.status ?? '') == 'dropoff'
          ? 'Pelanggan'
          : 'Merchant';

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant DriverMapPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldTarget = _destinationFor(oldWidget.job, oldWidget.snapshot);
    final newTarget = _routeDestination;
    if (_driverPoint == null) {
      _mapReady = false;
      _routePoints = const [];
      _routeDistanceMeters = null;
      _routeDurationSeconds = null;
      _routeLoading = false;
      _routeError = 'Pilih order dengan koordinat, atau aktifkan GPS untuk menampilkan peta.';
      return;
    }
    final targetChanged = oldTarget?.latitude != newTarget?.latitude ||
        oldTarget?.longitude != newTarget?.longitude ||
        oldWidget.job?.status != widget.job?.status ||
        oldWidget.job?.id != widget.job?.id;

    final oldPosition = oldWidget.snapshot?.position;
    final newPosition = widget.snapshot?.position;
    if (_mapReady && newPosition != null && (!newPosition.isMocked || kDebugMode)) {
      final changed = oldPosition == null ||
          _distanceMeters(
            LatLng(oldPosition.latitude, oldPosition.longitude),
            LatLng(newPosition.latitude, newPosition.longitude),
          ) >= 2;
      if (changed && _followGps) {
        _mapController.move(LatLng(newPosition.latitude, newPosition.longitude), _cameraZoom);
      }
      if (targetChanged || changed) _maybeLoadRoute(force: targetChanged);
    } else if (targetChanged && _mapReady) {
      _maybeLoadRoute(force: true);
    }
  }

  LatLng? _destinationFor(DriverJobView? job, LocationSnapshot? snapshot) {
    if (job == null || job.isCompleted) return null;
    if ((snapshot == null || (snapshot.mocked && !kDebugMode)) &&
        job.pickup != null && job.dropoff != null) return job.dropoff;
    switch (driverNavigationLegForStatus(job.status)) {
      case 'pickup':
        return job.pickup;
      case 'dropoff':
        return job.dropoff;
      default:
        return null;
    }
  }

  double _distanceMeters(LatLng a, LatLng b) {
    const radius = 6371000.0;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) *
            math.sin(dLng / 2) * math.sin(dLng / 2);
    return radius * 2 * math.atan2(math.sqrt(h), math.sqrt(math.max(0, 1 - h)));
  }

  Future<void> _maybeLoadRoute({bool force = false}) async {
    if (!_mapReady) return;

    final position = _hasUsableGps ? widget.snapshot?.position : null;
    final origin = position == null
        ? widget.job?.pickup
        : LatLng(position.latitude, position.longitude);
    final destination = position == null ? widget.job?.dropoff : _activeDestination;
    if (origin == null) {
      if (mounted) setState(() {
        _routeLoading = false;
        _routeError = 'Aktifkan lokasi perangkat untuk melihat rute dari posisi Anda.';
      });
      return;
    }

    if (destination == null) {
      if (mounted) {
        final status = widget.job?.status.toLowerCase() ?? '';
        final needsRoute = const ['assigned', 'accepted', 'picking_up', 'picked_up', 'delivering'].contains(status);
        final pickupAddress = widget.job?.pickupAddress.trim() ?? '';
        final dropoffAddress = widget.job?.dropoffAddress.trim() ?? '';
        final addressAvailable = const ['assigned', 'accepted', 'picking_up'].contains(status)
            ? pickupAddress.isNotEmpty && pickupAddress != '-'
            : dropoffAddress.isNotEmpty && dropoffAddress != '-';
        setState(() {
          _routePoints = const [];
          _routeDistanceMeters = null;
          _routeDurationSeconds = null;
          _routeLoading = false;
          _routeError = widget.job == null
              ? 'Pilih order untuk melihat rute jalan.'
              : needsRoute && addressAvailable
                  ? 'Alamat tujuan tersedia, tetapi koordinat tujuan belum dikirim oleh server.'
                  : needsRoute
                      ? 'Koordinat tujuan belum tersedia pada order ini.'
                      : 'Rute jalan tidak aktif pada status order ini.';
        });
      }
      return;
    }

    final now = DateTime.now();
    final destinationChanged = _lastRouteDestination == null ||
        _distanceMeters(_lastRouteDestination!, destination) > 8;
    final moved = _lastRouteOrigin == null ||
        _distanceMeters(_lastRouteOrigin!, origin) >= 45;
    final elapsed = _lastRouteRequestAt == null ||
        now.difference(_lastRouteRequestAt!).inSeconds >= 15;
    if (!force && !destinationChanged && !moved && !elapsed) return;
    if (_routeLoading && !force) return;

    final generation = ++_routeRequestGeneration;
    _lastRouteOrigin = origin;
    _lastRouteDestination = destination;
    _lastRouteRequestAt = now;
    setState(() {
      _routeLoading = true;
      _routeError = null;
      if (destinationChanged) {
        _routePoints = const [];
        _routeDistanceMeters = null;
        _routeDurationSeconds = null;
      }
    });

    try {
      final uri = Uri.https(
        'router.project-osrm.org',
        '/route/v1/driving/'
            '${origin.longitude.toStringAsFixed(6)},${origin.latitude.toStringAsFixed(6)};'
            '${destination.longitude.toStringAsFixed(6)},${destination.latitude.toStringAsFixed(6)}',
        const {
          'overview': 'full',
          'geometries': 'geojson',
          'steps': 'false',
        },
      );
      final response = await http.get(
        uri,
        headers: const {'Accept': 'application/json', 'User-Agent': 'BersolekMart-Mobile/1.0'},
      ).timeout(const Duration(seconds: 9));
      if (response.statusCode != 200) {
        throw FormatException('Routing service returned HTTP ${response.statusCode}.');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['code'] != 'Ok' || decoded['routes'] is! List ||
          (decoded['routes'] as List).isEmpty) {
        throw const FormatException('Routing service did not return a road route.');
      }
      final route = Map<String, dynamic>.from((decoded['routes'] as List).first as Map);
      final geometry = route['geometry'];
      if (geometry is! Map || geometry['coordinates'] is! List) {
        throw const FormatException('Road-route geometry is unavailable.');
      }
      final points = <LatLng>[];
      for (final raw in geometry['coordinates'] as List) {
        if (raw is List && raw.length >= 2) {
          final longitude = double.tryParse(raw[0].toString());
          final latitude = double.tryParse(raw[1].toString());
          if (latitude != null && longitude != null &&
              latitude.abs() <= 90 && longitude.abs() <= 180) {
            points.add(LatLng(latitude, longitude));
          }
        }
      }
      if (points.length < 2) {
        throw const FormatException('Road route contains insufficient geometry points.');
      }
      if (!mounted || generation != _routeRequestGeneration) return;
      setState(() {
        _routePoints = points;
        _routeDistanceMeters = _asDouble(route['distance']);
        _routeDurationSeconds = _asDouble(route['duration']);
        _routeLoading = false;
        _routeError = null;
      });
    } catch (error) {
      if (!mounted || generation != _routeRequestGeneration) return;
      setState(() {
        _routeLoading = false;
        _routeError = _routePoints.isEmpty
            ? 'Rute jalan belum tersedia. Periksa koneksi atau koordinat order.'
            : 'Rute terakhir masih ditampilkan; pembaruan rute gagal.';
      });
      if (kDebugMode) debugPrint('[BersolekMart Routing] ${error.runtimeType}: route refresh failed.');
    }
  }

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  void _centerOnDriver() {
    final snapshot = widget.snapshot;
    if (snapshot == null || !_hasUsableGps) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lokasi perangkat belum tersedia. Aktifkan GPS, lalu coba lagi.')),
      );
      return;
    }
    setState(() => _followGps = true);
    _cameraZoom = _cameraZoom < 15 ? 15 : _cameraZoom;
    if (_mapReady) _mapController.move(LatLng(snapshot.position.latitude, snapshot.position.longitude), _cameraZoom);
    _maybeLoadRoute(force: true);
  }

  void _openFullscreen() => widget.onFullscreenChanged?.call(true);

  void _closeFullscreen() => widget.onFullscreenChanged?.call(false);

  @override
  Widget build(BuildContext context) {
    final destination = _activeDestination;
    final snapshot = widget.snapshot;
    final hasValidGps = _hasUsableGps;
    final simulatedGps = snapshot?.mocked == true && kDebugMode;
    final initialCenter = _driverPoint;
    if (initialCenter == null) _mapReady = false;

    return Stack(
      children: [
        if (initialCenter != null)
          FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: 14,
            initialCameraFit: widget.job?.pickup != null && widget.job?.dropoff != null
                ? CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints([widget.job!.pickup!, widget.job!.dropoff!]),
                    padding: const EdgeInsets.fromLTRB(56, 110, 56, 310),
                  )
                : null,
            onMapReady: () {
              _mapReady = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                if (snapshot != null && hasValidGps && _followGps) _mapController.move(LatLng(snapshot.position.latitude, snapshot.position.longitude), _cameraZoom);
                _maybeLoadRoute(force: true);
              });
            },
            onPositionChanged: (camera, hasGesture) {
              _cameraZoom = camera.zoom;
              if (hasGesture && _followGps && mounted) {
                setState(() => _followGps = false);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.bersolekmart.mobile',
            ),
            if (_routePoints.length >= 2) ...[
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _routePoints,
                    strokeWidth: 9,
                    color: Colors.white.withAlpha(220),
                  ),
                ],
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _routePoints,
                    strokeWidth: 5,
                    color: const Color(0xFFD20A2E),
                  ),
                ],
              ),
            ],
            MarkerLayer(
              markers: [
                if (snapshot != null && hasValidGps)
                  Marker(
                    point: LatLng(snapshot.position.latitude, snapshot.position.longitude),
                    width: 54,
                    height: 54,
                    child: Transform.rotate(
                      angle: (snapshot.position.heading.isFinite ? snapshot.position.heading : 0) * math.pi / 180,
                      child: const _MapMarker(
                        icon: Icons.navigation_rounded,
                        color: Color(0xFF171113),
                      ),
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
                      color: Color(0xFFD20A2E),
                    ),
                  ),
              ],
            ),
            RichAttributionWidget(
              attributions: const [TextSourceAttribution('OpenStreetMap contributors')],
            ),
          ],
        )
        else
          Positioned.fill(
            child: Container(
              color: const Color(0xFFEAECEF),
              alignment: Alignment.center,
              padding: const EdgeInsets.fromLTRB(34, 100, 34, 220),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Icon(Icons.my_location_rounded, color: Color(0xFFD20A2E), size: 34),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Menunggu lokasi yang valid',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF171113)),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'Peta akan mengikuti GPS driver atau koordinat order dari server. Lokasi tidak dibuat otomatis.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF665C60), height: 1.45, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(
              children: [
                if (widget.fullscreen)
                  _MapActionButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Kembali ke peta order',
                    onPressed: _closeFullscreen,
                  )
                else
                  _MapChip(
                    icon: hasValidGps ? Icons.my_location_rounded : Icons.location_searching_rounded,
                    label: _previewOnly ? 'Pratinjau rute order' : widget.job == null ? 'Peta pengantaran' : 'Menuju $_destinationLabel',
                  ),
                const Spacer(),
                _MapActionButton(
                  icon: _followGps ? Icons.gps_fixed_rounded : Icons.my_location_rounded,
                  tooltip: _followGps ? 'Ikuti GPS aktif' : 'Ikuti pergerakan GPS',
                  onPressed: _centerOnDriver,
                ),
                if (!widget.fullscreen) ...[
                  const SizedBox(width: 8),
                  _MapActionButton(
                    icon: Icons.fullscreen_rounded,
                    tooltip: 'Buka peta layar penuh',
                    onPressed: _openFullscreen,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (!widget.fullscreen)
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .48),
                  child: SingleChildScrollView(
                    child: _MapSheet(
                  job: widget.job,
                  gpsReady: hasValidGps,
                  simulatedGps: simulatedGps,
                  previewOnly: _previewOnly,
                  routeLoading: _routeLoading,
                  routeError: _routeError,
                  routeDistanceMeters: _routeDistanceMeters,
                  routeDurationSeconds: _routeDurationSeconds,
                  routeReady: _routePoints.length >= 2,
                  onFollowGps: _centerOnDriver,
                  onNavigate: widget.job == null || destination == null
                      ? null
                      : () => _openRoadNavigation(context, widget.job!, snapshot: widget.snapshot),
                ),
              ),
            ),
          )
        else if (widget.job != null)
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: _FullscreenRouteCard(
                  job: widget.job!,
                  previewOnly: _previewOnly,
                  routeDistanceMeters: _routeDistanceMeters,
                  routeDurationSeconds: _routeDurationSeconds,
                  routeReady: _routePoints.length >= 2,
                  onFollowGps: _centerOnDriver,
                  onNavigate: destination == null
                      ? null
                      : () => _openRoadNavigation(context, widget.job!, snapshot: widget.snapshot),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String _routeDistanceLabel(double? meters) {
  if (meters == null || !meters.isFinite || meters < 0) return 'Jarak menunggu';
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

String _routeDurationLabel(double? seconds) {
  if (seconds == null || !seconds.isFinite || seconds < 0) return 'Waktu menunggu';
  final minutes = (seconds / 60).round();
  if (minutes < 60) return '$minutes menit';
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return remainder == 0 ? '$hours jam' : '$hours jam $remainder mnt';
}

class _MapActionButton extends StatelessWidget {
  const _MapActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF171113),
      elevation: 7,
      borderRadius: BorderRadius.circular(15),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        color: Colors.white,
        icon: Icon(icon),
      ),
    );
  }
}

class _FullscreenRouteCard extends StatelessWidget {
  const _FullscreenRouteCard({
    required this.job,
    required this.previewOnly,
    required this.routeDistanceMeters,
    required this.routeDurationSeconds,
    required this.routeReady,
    required this.onFollowGps,
    required this.onNavigate,
  });

  final DriverJobView job;
  final bool previewOnly;
  final double? routeDistanceMeters;
  final double? routeDurationSeconds;
  final bool routeReady;
  final VoidCallback onFollowGps;
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF24191C), Color(0xFF111111)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x55D20A2E)),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 22, offset: Offset(0, 8))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.route_rounded, color: Color(0xFFFF405D)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Rute pengantaran',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
              ),
              Text(job.code, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          Text(job.storeName, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          Text(job.pickupAddress, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(color: Color(0x44FFFFFF), height: 1),
          ),
          Text(job.customerName, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          Text(job.dropoffAddress, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.route_outlined, size: 17, color: Color(0xFFFF9CAB)),
              const SizedBox(width: 7),
              Expanded(child: Text(
                routeReady
                    ? '${previewOnly ? 'Pratinjau merchant → pelanggan · ' : ''}${_routeDistanceLabel(routeDistanceMeters)} · ${_routeDurationLabel(routeDurationSeconds)}'
                    : 'Jarak dan waktu tersedia saat rute jalan berhasil dimuat',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
              )),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onFollowGps,
              icon: const Icon(Icons.my_location_rounded),
              label: const Text('Ikuti GPS di peta ini'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD20A2E)),
            ),
          ),
          if (onNavigate != null)
            Align(
              alignment: Alignment.center,
              child: TextButton.icon(
                onPressed: onNavigate,
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Buka Google Maps (opsional)'),
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Peta © OpenStreetMap contributors · Rute jalan OSRM',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, fontSize: 10),
            ),
          ),
        ],
      ),
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
  const DriverProfile({
    super.key,
    required this.snapshot,
    required this.onOpenMap,
  });

  final LocationSnapshot? snapshot;
  final VoidCallback onOpenMap;

  void _openVehiclePage(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DriverVehiclePage()));
  }

  void _openBanksPage(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BankAccountsPage(title: 'Rekening Pencairan')));
  }

  void _openBaseLocationPage(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DriverBaseLocationPage()));
  }

  void _openDetails(BuildContext context, String title, IconData icon, Map<String, dynamic> user, List<String> keys, String emptyText) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _DriverAccountDetailPage(title: title, icon: icon, user: user, keys: keys, emptyText: emptyText),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final user = session?.user ?? const <String, dynamic>{};
    final name = readableDriverValue(user['full_name'], fallback: 'Driver');

    Widget tile(IconData icon, String title, String subtitle, VoidCallback onTap) => Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: const Color(0xFFE0F5EA), borderRadius: BorderRadius.circular(13)),
          child: Icon(icon, color: const Color(0xFF147D58)),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Akun Driver')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 110),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF0E6D50), Color(0xFF123C32)]),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(children: [
              CircleAvatar(
                radius: 31,
                backgroundColor: Colors.white24,
                child: Text(name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                const Text('Driver BersolekMart', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 7),
                Text(readableDriverValue(user['phone'] ?? user['email']),
                  style: const TextStyle(color: Colors.white)),
              ])),
            ]),
          ),
          const SizedBox(height: 20),
          const Text('Akun dan Pengaturan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          tile(Icons.person_outline_rounded, 'Profil Saya', 'Informasi akun dan kontak',
            () async {
              final saved = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
                builder: (_) => AccountProfileEditPage(title: 'Profil Driver', initialUser: user),
              ));
              if (saved == true && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profil berhasil diperbarui.')));
              }
            }),
          const SizedBox(height: 8),
          tile(Icons.two_wheeler_rounded, 'Kendaraan', 'Informasi kendaraan yang terdaftar',
            () => _openVehiclePage(context)),
          const SizedBox(height: 8),
          tile(Icons.account_balance_outlined, 'Rekening Pencairan', 'Tambah atau kelola rekening driver',
            () => _openBanksPage(context)),
          const SizedBox(height: 8),
          tile(Icons.location_on_outlined, 'Alamat Akun', 'Tambah, edit, dan pilih alamat driver',
            () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const MemberAddressBookPage(title: 'Alamat Driver'),
            ))),
          const SizedBox(height: 8),
          tile(Icons.home_work_outlined, 'Alamat dan Titik Pangkal', 'Simpan GPS pangkal dan radius layanan driver',
            () => _openBaseLocationPage(context)),
          const SizedBox(height: 8),
          tile(Icons.shield_outlined, 'Keamanan Lokasi',
            snapshot?.mocked == true ? 'Lokasi mencurigakan terdeteksi' : 'Status pemantauan lokasi perangkat',
            () => _openDetails(context, 'Keamanan Lokasi', Icons.shield_outlined, {
              'status': snapshot == null ? 'Belum ada data GPS' : snapshot!.mocked ? 'Mock location terdeteksi' : 'Tidak terdeteksi sebagai mock pada pemeriksaan terakhir',
              'akurasi': snapshot == null ? null : '${snapshot!.position.accuracy.toStringAsFixed(0)} meter',
              'pergerakan': snapshot == null ? null : snapshot!.movementAnomaly ? 'Perlu diverifikasi' : 'Tidak ada anomali pada pemeriksaan terakhir',
            }, const ['status', 'akurasi', 'pergerakan'], 'Status lokasi belum tersedia.')),
          const SizedBox(height: 8),
          tile(Icons.map_outlined, 'Peta dan Navigasi', 'Buka peta order yang dipilih', onOpenMap),
          const SizedBox(height: 8),
          tile(Icons.settings_outlined, 'Pengaturan', 'Preferensi aplikasi dan privasi',
            () => _openDetails(context, 'Pengaturan', Icons.settings_outlined, const <String, dynamic>{},
              const [], 'Pengaturan akun tersinkronisasi belum tersedia dari API mobile.')),
          const SizedBox(height: 8),
          tile(Icons.support_agent_outlined, 'Bantuan Driver', 'Panduan penggunaan aplikasi',
            () => _openDetails(context, 'Bantuan Driver', Icons.support_agent_outlined, const <String, dynamic>{},
              const [], 'Untuk panduan order, pickup, dan pengantaran, gunakan kanal bantuan resmi BersolekMart.')),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFD20A2E),
              side: const BorderSide(color: Color(0xFFD20A2E)),
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Keluar dari akun'),
          ),
        ],
      ),
    );
  }
}

class _DriverAccountDetailPage extends StatelessWidget {
  const _DriverAccountDetailPage({
    required this.title,
    required this.icon,
    required this.user,
    required this.keys,
    required this.emptyText,
  });

  final String title;
  final IconData icon;
  final Map<String, dynamic> user;
  final List<String> keys;
  final String emptyText;

  String _label(String key) {
    const labels = {
      'full_name': 'Nama lengkap', 'name': 'Nama', 'email': 'Email',
      'phone': 'Nomor telepon', 'nik': 'NIK', 'vehicle': 'Kendaraan',
      'vehicle_type': 'Jenis kendaraan', 'vehicle_plate': 'Nomor polisi',
      'plate_number': 'Nomor polisi', 'license_plate': 'Nomor polisi',
      'bank_account': 'Rekening', 'bank_name': 'Nama bank', 'bank_code': 'Kode bank',
      'account_name': 'Nama pemilik rekening', 'account_number': 'Nomor rekening',
      'status': 'Status lokasi', 'akurasi': 'Akurasi GPS', 'pergerakan': 'Pemeriksaan pergerakan',
    };
    return labels[key] ?? key.replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final fields = keys.where((key) => user[key] != null && readableDriverValue(user[key], fallback: '').isNotEmpty).toList();
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: fields.isEmpty
          ? Center(child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 52, color: const Color(0xFF147D58)),
                const SizedBox(height: 14),
                Text(emptyText, textAlign: TextAlign.center, style: const TextStyle(height: 1.5)),
              ]),
            ))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final key in fields)
                  Card(child: ListTile(
                    title: Text(_label(key), style: const TextStyle(color: Colors.black54, fontSize: 12)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(readableDriverValue(user[key]), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                  )),
                const SizedBox(height: 10),
                const Text(
                  'Halaman ini menampilkan data yang tersedia di sesi/API akun. Perubahan hanya diaktifkan setelah endpoint backend terkait terverifikasi.',
                  style: TextStyle(color: Colors.black54, height: 1.45),
                ),
              ],
            ),
    );
  }
}

class DriverVehiclePage extends ConsumerStatefulWidget {
  const DriverVehiclePage({super.key});

  @override
  ConsumerState<DriverVehiclePage> createState() => _DriverVehiclePageState();
}

class _DriverVehiclePageState extends ConsumerState<DriverVehiclePage> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final payload = await ref.read(apiClientProvider).get('/driver/profile');
    return Map<String, dynamic>.from(payload is Map && payload['data'] is Map ? payload['data'] as Map : const {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Kendaraan')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) {
          return _ErrorCard(
            message: 'Data kendaraan belum dapat dimuat. Pastikan endpoint /driver/profile sudah tersedia.',
            onRetry: () async { setState(() => _future = _load()); },
          );
        }
        final data = snapshot.data ?? const {};
        final fields = <String, String>{
          'Jenis kendaraan': readableDriverValue(data['vehicle_type'], fallback: 'Belum diatur'),
          'Nomor polisi': readableDriverValue(data['vehicle_plate'], fallback: 'Belum diisi'),
          'Wilayah layanan': readableDriverValue(data['service_area'], fallback: 'Belum diatur'),
          'Status driver': readableDriverValue(data['status'], fallback: 'Belum diketahui'),
        };
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final entry in fields.entries)
              Card(child: ListTile(
                title: Text(entry.key, style: const TextStyle(color: Colors.black54, fontSize: 12)),
                subtitle: Padding(padding: const EdgeInsets.only(top: 5), child: Text(entry.value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              )),
            const SizedBox(height: 8),
            const Text('Informasi ini dibaca dari profil driver backend. Perubahan kendaraan tetap mengikuti proses yang tersedia di PWA/operator.',
              style: TextStyle(color: Colors.black54, height: 1.45)),
          ],
        );
      },
    ),
  );
}

class DriverBankAccountsPage extends ConsumerStatefulWidget {
  const DriverBankAccountsPage({super.key});

  @override
  ConsumerState<DriverBankAccountsPage> createState() => _DriverBankAccountsPageState();
}

class _DriverBankAccountsPageState extends ConsumerState<DriverBankAccountsPage> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<dynamic>> _load() async {
    final payload = await ref.read(apiClientProvider).get('/banks');
    return List<dynamic>.from(payload is Map ? payload['data'] as List? ?? const [] : const []);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Rekening Pencairan')),
    body: FutureBuilder<List<dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) {
          return _ErrorCard(
            message: 'Rekening belum dapat dimuat. Pastikan endpoint /banks sudah tersedia.',
            onRetry: () async { setState(() => _future = _load()); },
          );
        }
        final items = snapshot.data ?? const [];
        if (items.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.account_balance_outlined, size: 52, color: Color(0xFF147D58)),
                SizedBox(height: 12),
                Text('Belum ada rekening pencairan.', style: TextStyle(fontWeight: FontWeight.w800)),
                SizedBox(height: 6),
                Text('Pengelolaan rekening tetap mengikuti proses PWA sampai endpoint simpan mobile digunakan.', textAlign: TextAlign.center),
              ]),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final item = Map<String, dynamic>.from(items[index] as Map);
            final number = readableDriverValue(item['account_number'], fallback: '');
            final digits = number.replaceAll(RegExp(r'[^0-9]'), '');
            final masked = digits.length > 4 ? '•••• ${digits.substring(digits.length - 4)}' : number;
            final isDefault = item['is_default']?.toString() == '1' || item['is_default'] == true;
            return Card(child: ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFFE0F5EA), child: Icon(Icons.account_balance_outlined, color: Color(0xFF147D58))),
              title: Text(readableDriverValue(item['bank_name'], fallback: 'Bank'), style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text('${readableDriverValue(item['account_name'], fallback: 'Pemilik rekening')}\n$masked'),
              trailing: isDefault ? const Chip(label: Text('Utama')) : null,
            ));
          },
        );
      },
    ),
  );
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
        gradient: LinearGradient(
          colors: mocked
              ? const [Color(0xFF3B1C22), Color(0xFF84212F)]
              : online
                  ? const [Color(0xFF24191C), Color(0xFF8B001F)]
                  : const [Color(0xFF21191B), Color(0xFF433338)],
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
                _StatusChip(status: job.statusLabel),
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
            buttonText: 'Detail Order',
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

Future<void> _openRoadNavigation(
  BuildContext context,
  DriverJobView job, {
  LocationSnapshot? snapshot,
}) async {
  final goingToCustomer = driverNavigationLegForStatus(job.status) == 'dropoff';
  final point = goingToCustomer ? job.dropoff : job.pickup;
  final address = goingToCustomer ? job.dropoffAddress : job.pickupAddress;
  final destination = point != null
      ? '${point.latitude},${point.longitude}'
      : (address.trim().isEmpty || address == '-' ? '' : address.trim());

  if (destination.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(goingToCustomer
          ? 'Koordinat/alamat pelanggan belum tersedia di order.'
          : 'Koordinat/alamat merchant belum tersedia di order.')),
    );
    return;
  }

  final nativeUri = Uri.parse('google.navigation:q=${Uri.encodeComponent(destination)}&mode=d');
  final directionsUri = Uri.https('www.google.com', '/maps/dir/', {
    if (snapshot != null && !snapshot.mocked)
      'origin': '${snapshot.position.latitude},${snapshot.position.longitude}',
    'destination': destination,
    'travelmode': 'driving',
    'dir_action': 'navigate',
  });

  try {
    final openedNative = await launchUrl(nativeUri, mode: LaunchMode.externalApplication);
    if (openedNative || !context.mounted) return;
    final openedDirections = await launchUrl(directionsUri, mode: LaunchMode.externalApplication);
    if (!openedDirections && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aplikasi navigasi tidak dapat dibuka. Rute jalan tetap terlihat pada peta aplikasi.')),
      );
    }
  } catch (_) {
    if (!context.mounted) return;
    try {
      final opened = await launchUrl(directionsUri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Navigasi eksternal tidak tersedia. Rute jalan di peta aplikasi tetap dapat digunakan.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Navigasi eksternal gagal dibuka. Aplikasi BersolekMart tetap aktif.')),
        );
      }
    }
  }
}

class _MapSheet extends StatelessWidget {
  const _MapSheet({
    required this.job,
    required this.gpsReady,
    required this.simulatedGps,
    required this.previewOnly,
    required this.routeLoading,
    required this.routeError,
    required this.routeDistanceMeters,
    required this.routeDurationSeconds,
    required this.routeReady,
    required this.onFollowGps,
    required this.onNavigate,
  });

  final DriverJobView? job;
  final bool gpsReady;
  final bool simulatedGps;
  final bool previewOnly;
  final bool routeLoading;
  final String? routeError;
  final double? routeDistanceMeters;
  final double? routeDurationSeconds;
  final bool routeReady;
  final VoidCallback onFollowGps;
  final VoidCallback? onNavigate;

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
                backgroundColor: Color(0xFFFFE5E9),
                child: Icon(Icons.map_outlined, color: Color(0xFFD20A2E)),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text('Pilih order untuk melihat pickup, tujuan, dan rute jalan.',
                  style: TextStyle(fontWeight: FontWeight.w700, height: 1.4)),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 12,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: Text(job!.code,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900))),
                _StatusChip(status: job!.statusLabel),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Icon(
                  gpsReady ? Icons.gps_fixed_rounded : Icons.gps_off_rounded,
                  size: 16,
                  color: gpsReady ? const Color(0xFF147D58) : Colors.black45,
                ),
                const SizedBox(width: 6),
                Expanded(child: Text(
                  simulatedGps ? 'Lokasi simulator · tidak dikirim ke server' :
                  gpsReady ? 'GPS aktif · posisi mengikuti pergerakan' : 'Lokasi perangkat belum tersedia',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                )),
              ],
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
              color: const Color(0xFFD20A2E),
              title: job!.customerName,
              address: job!.dropoffAddress,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F2F3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  if (routeLoading)
                    const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD20A2E)),
                    )
                  else
                    Icon(
                      routeReady ? Icons.alt_route_rounded : Icons.route_outlined,
                      color: routeReady ? const Color(0xFF147D58) : const Color(0xFFD20A2E),
                      size: 18,
                    ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    routeLoading
                        ? 'Menghitung rute jalan…'
                        : routeReady
                            ? '${_routeDistanceLabel(routeDistanceMeters)} · ${_routeDurationLabel(routeDurationSeconds)}'
                            : (routeError ?? 'Aktifkan GPS untuk menghitung rute jalan.'),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      fontWeight: routeReady ? FontWeight.w900 : FontWeight.w600,
                      color: routeReady ? const Color(0xFF147D58) : const Color(0xFF665C60),
                    ),
                  )),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (routeReady)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  'Estimasi jarak/waktu dari routing jalan; belum memakai data lalu lintas real-time.',
                  style: TextStyle(color: Colors.black45, fontSize: 10, height: 1.35),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onFollowGps,
                icon: const Icon(Icons.my_location_rounded),
                label: const Text('Ikuti GPS di peta ini'),
              ),
            ),
            if (onNavigate != null)
              Center(
                child: TextButton.icon(
                  onPressed: onNavigate,
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Buka Google Maps (opsional)'),
                ),
              ),
            const Padding(
              padding: EdgeInsets.only(top: 7),
              child: Text(
                'Peta © OpenStreetMap contributors · Rute jalan OSRM',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black45, fontSize: 10),
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
