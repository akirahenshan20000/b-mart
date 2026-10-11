import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_controller.dart';
import '../account/member_data_pages.dart';

Map<String, dynamic> _checkoutMap(dynamic payload) =>
    payload is Map && payload['data'] is Map
        ? Map<String, dynamic>.from(payload['data'] as Map)
        : <String, dynamic>{};

List<dynamic> _checkoutList(dynamic payload) =>
    payload is Map && payload['data'] is List
        ? List<dynamic>.from(payload['data'] as List)
        : <dynamic>[];

num _checkoutNumber(dynamic raw) {
  if (raw is num) return raw;
  return num.tryParse(raw?.toString() ?? '') ?? 0;
}

String _checkoutRupiah(dynamic raw) {
  final value = raw is num ? raw.round() : int.tryParse(raw?.toString() ?? '') ?? double.tryParse(raw?.toString() ?? '')?.round() ?? 0;
  final digits = value.abs().toString();
  final output = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) output.write('.');
    output.write(digits[i]);
  }
  return 'Rp ${value < 0 ? '-' : ''}$output';
}

class CustomerCheckoutPage extends ConsumerStatefulWidget {
  const CustomerCheckoutPage({super.key});

  @override
  ConsumerState<CustomerCheckoutPage> createState() => _CustomerCheckoutPageState();
}

class _CustomerCheckoutPageState extends ConsumerState<CustomerCheckoutPage> {
  late Future<void> _future;
  List<dynamic> _addresses = const [];
  List<dynamic> _rates = const [];
  List<String> _paymentMethods = const [];
  Map<String, dynamic> _cart = const {};
  Map<String, dynamic> _options = const {};
  int? _addressId;
  int _selectedRateIndex = 0;
  String? _paymentMethod;
  Position? _position;
  bool _loadingGps = false;
  bool _ratesLoading = false;
  bool _submitting = false;
  Map<String, dynamic>? _placedOrder;
  Map<String, dynamic>? _placedPayment;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    final values = await Future.wait([
      api.get('/checkout/options'),
      api.get('/addresses'),
      api.get('/cart'),
    ]);
    final options = _checkoutMap(values[0]);
    final addresses = _checkoutList(values[1]);
    final cart = _checkoutMap(values[2]);
    final rawItems = cart['items'] is List ? List<dynamic>.from(cart['items'] as List) : <dynamic>[];
    if (!mounted) return;
    setState(() {
      _options = options;
      _addresses = addresses;
      _cart = cart;
      final methods = options['payment_methods'] is List
          ? List<dynamic>.from(options['payment_methods'] as List)
          : <dynamic>[];
      _paymentMethods = methods.map((value) => value.toString()).where((value) => value.isNotEmpty).toList();
      if (_addressId == null || !addresses.any((value) => int.tryParse((value as Map)['id']?.toString() ?? '') == _addressId)) {
        final preferred = addresses.firstWhere(
          (value) => value is Map && (value['is_default'] == true || value['is_default']?.toString() == '1'),
          orElse: () => addresses.isNotEmpty ? addresses.first : null,
        );
        _addressId = preferred is Map ? int.tryParse(preferred['id']?.toString() ?? '') : null;
      }
      if (_paymentMethod == null || !_paymentMethods.contains(_paymentMethod)) {
        _paymentMethod = _paymentMethods.isEmpty ? null : _paymentMethods.first;
      }
      if (rawItems.isEmpty) _rates = const [];
      _lastError = null;
    });
  }

  Future<void> _reloadAll() async {
    setState(() {
      _future = _load();
      _lastError = null;
    });
    await _future;
  }

  Future<void> _manageAddresses() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const MemberAddressBookPage()),
    );
    if (mounted) await _reloadAll();
  }

  Future<void> _captureGps() async {
    setState(() {
      _loadingGps = true;
      _lastError = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw StateError('Izin lokasi ditolak. Izinkan lokasi presisi untuk melanjutkan checkout.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
      );
      if (!mounted) return;
      final maxAccuracy = (_options['location_max_accuracy_m'] as num?)?.toDouble() ?? 500;
      setState(() => _position = position);
      if (position.accuracy > maxAccuracy) {
        setState(() => _lastError = 'Akurasi GPS ${position.accuracy.toStringAsFixed(0)} m belum memenuhi batas ${maxAccuracy.toStringAsFixed(0)} m. Cari area dengan sinyal lebih baik dan ambil lokasi lagi.');
      } else {
        await _loadRates();
      }
    } catch (error) {
      if (mounted) setState(() => _lastError = error is StateError ? error.message : 'Lokasi gagal didapat. Periksa izin perangkat dan coba lagi.');
    } finally {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  Future<void> _loadRates() async {
    if (_position == null) {
      setState(() => _lastError = 'Ambil lokasi perangkat terlebih dahulu untuk menghitung ongkir.');
      return;
    }
    setState(() {
      _ratesLoading = true;
      _lastError = null;
    });
    try {
      final payload = await ref.read(apiClientProvider).get('/checkout/rates', query: {
        'city': 'Kota Probolinggo',
        'lat': _position!.latitude.toString(),
        'lng': _position!.longitude.toString(),
      });
      final rates = _checkoutList(payload);
      if (!mounted) return;
      setState(() {
        _rates = rates;
        _selectedRateIndex = 0;
      });
    } catch (_) {
      if (mounted) setState(() => _lastError = 'Ongkos kirim belum bisa dihitung dari server. Coba ambil GPS dan muat ulang ongkir.');
    } finally {
      if (mounted) setState(() => _ratesLoading = false);
    }
  }

  Future<void> _placeOrder() async {
    final addressId = _addressId;
    final pos = _position;
    final maxAccuracy = (_options['location_max_accuracy_m'] as num?)?.toDouble() ?? 500;
    if (addressId == null) {
      setState(() => _lastError = 'Pilih atau tambahkan alamat pengiriman terlebih dahulu.');
      return;
    }
    if (_options['can_checkout'] == false || _options['can_checkout']?.toString() == '0') {
      setState(() => _lastError = 'Akun belum memenuhi persyaratan checkout pada mode marketplace saat ini. Periksa status akun di PWA.');
      return;
    }
    if (_options['requires_device_location'] != false && _options['requires_device_location']?.toString() != '0') {
      if (pos == null) {
        setState(() => _lastError = 'Lokasi perangkat wajib diizinkan sebelum checkout.');
        return;
      }
      if (pos.accuracy <= 0 || pos.accuracy > maxAccuracy) {
        setState(() => _lastError = 'Akurasi GPS belum memenuhi batas server. Ambil lokasi dengan akurasi lebih baik.');
        return;
      }
    }
    if (_rates.isEmpty) {
      setState(() => _lastError = 'Ongkos kirim belum tersedia. Ambil GPS lalu hitung ongkir sebelum checkout.');
      return;
    }
    final selectedRate = _selectedRateIndex >= 0 && _selectedRateIndex < _rates.length
        ? _rates[_selectedRateIndex]
        : null;
    if (selectedRate is! Map || _paymentMethod == null) {
      setState(() => _lastError = 'Pilih layanan pengiriman dan metode pembayaran.');
      return;
    }
    setState(() {
      _submitting = true;
      _lastError = null;
    });
    try {
      final response = await ref.read(apiClientProvider).post('/checkout', {
        'address_id': addressId,
        if (pos != null) 'guest_latitude': pos.latitude,
        if (pos != null) 'guest_longitude': pos.longitude,
        if (pos != null) 'guest_accuracy': pos.accuracy,
        'shipping_method': (selectedRate['method'] ?? 'SOPIR').toString(),
        'shipping_rate_id': int.tryParse(selectedRate['id']?.toString() ?? '') ?? 0,
        'payment_method': _paymentMethod,
      });
      final data = _checkoutMap(response);
      final order = data['order'] is Map ? Map<String, dynamic>.from(data['order'] as Map) : <String, dynamic>{};
      final payment = data['payment'] is Map ? Map<String, dynamic>.from(data['payment'] as Map) : <String, dynamic>{};
      if (order.isEmpty || order['code'] == null) throw StateError('Server tidak mengembalikan kode pesanan.');
      if (!mounted) return;
      setState(() {
        _placedOrder = order;
        _placedPayment = payment;
      });
    } catch (_) {
      if (mounted) setState(() => _lastError = 'Checkout ditolak atau gagal diproses oleh server. Periksa alamat, stok, lokasi, dan metode pembayaran; tidak ada pembayaran yang diasumsikan berhasil.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _continuePayment() async {
    final order = _placedOrder;
    final payment = _placedPayment;
    if (order == null || payment == null) return;
    if ((payment['provider'] ?? '').toString().toUpperCase() != 'MOCK_BANK_JATIM') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Status pembayaran mengikuti penyedia/backend. Aplikasi tidak menandai pembayaran secara manual.')),
      );
      return;
    }
    final code = Uri.encodeComponent(order['code'].toString());
    final uri = Uri.https('bersolekmart.com', '/payment/mock/$code');
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Halaman pembayaran belum dapat dibuka. Coba lagi atau lanjutkan dari PWA.')));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Halaman pembayaran gagal dibuka. Status order tetap mengikuti server.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Checkout')),
    body: FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) {
          return _CheckoutError(
            message: 'Checkout belum dapat dimuat. Pastikan endpoint profil mobile, checkout/options, cart, dan alamat sudah dipasang pada API.',
            onRetry: _reloadAll,
          );
        }
        if (_placedOrder != null) {
          return _OrderCreatedView(
            order: _placedOrder!,
            payment: _placedPayment ?? const {},
            onContinuePayment: _continuePayment,
            onDone: () => Navigator.of(context).pop(true),
          );
        }
        final items = _cart['items'] is List ? List<dynamic>.from(_cart['items'] as List) : <dynamic>[];
        final subtotal = _cart['subtotal'] ?? 0;
        final selectedAddress = _addresses.firstWhere(
          (v) => v is Map && int.tryParse(v['id']?.toString() ?? '') == _addressId,
          orElse: () => null,
        );
        final maxAccuracy = (_options['location_max_accuracy_m'] as num?)?.toDouble() ?? 500;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            if (items.isEmpty) const _CheckoutNotice(
              icon: Icons.shopping_basket_outlined,
              title: 'Keranjang kosong',
              message: 'Tambahkan produk sebelum melanjutkan checkout.',
            ) else Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Ringkasan belanja', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  for (final raw in items)
                    if (raw is Map)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(children: [
                          Expanded(child: Text('${raw['name'] ?? 'Produk'} × ${raw['qty'] ?? 1}')),
                          Text(_checkoutRupiah(_checkoutNumber(raw['unit_price'] ?? raw['variant_price'] ?? raw['sale_price'] ?? raw['price']))),
                        ]),
                      ),
                  const Divider(height: 22),
                  Row(children: [
                    const Expanded(child: Text('Subtotal')),
                    Text(_checkoutRupiah(subtotal), style: const TextStyle(fontWeight: FontWeight.w900)),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Expanded(child: Text('Alamat pengiriman', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
                    IconButton(onPressed: _manageAddresses, tooltip: 'Kelola alamat', icon: const Icon(Icons.edit_location_alt_outlined)),
                  ]),
                  if (_addresses.isEmpty)
                    const _CheckoutNotice(icon: Icons.location_off_outlined, title: 'Belum ada alamat tersimpan', message: 'Tambahkan alamat sebelum checkout.')
                  else ...[
                    DropdownButtonFormField<int>(
                      initialValue: _addressId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Pilih alamat'),
                      items: _addresses.map((raw) {
                        final address = Map<String, dynamic>.from(raw as Map);
                        return DropdownMenuItem<int>(
                          value: int.tryParse(address['id']?.toString() ?? ''),
                          child: Text('${address['label'] ?? 'Alamat'} · ${address['village'] ?? ''}', overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (value) => setState(() {
                        _addressId = value;
                        _rates = const [];
                        _selectedRateIndex = 0;
                      }),
                    ),
                    if (selectedAddress is Map)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '${selectedAddress['recipient_name'] ?? ''}\n${selectedAddress['phone'] ?? ''}\n${selectedAddress['address_line'] ?? ''}, ${selectedAddress['village'] ?? ''}, ${selectedAddress['district'] ?? ''}',
                          style: const TextStyle(color: Colors.black54, height: 1.4),
                        ),
                      ),
                    Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _manageAddresses, icon: const Icon(Icons.add), label: const Text('Tambah atau edit alamat'))),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Lokasi perangkat', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(_position == null
                      ? 'PWA memerlukan lokasi presisi untuk memvalidasi checkout.'
                      : 'Akurasi GPS: ${_position!.accuracy.toStringAsFixed(0)} m (batas ${maxAccuracy.toStringAsFixed(0)} m).',
                    style: const TextStyle(color: Colors.black54)),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _loadingGps ? null : _captureGps,
                    icon: _loadingGps
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location_rounded),
                    label: Text(_loadingGps ? 'Mengambil lokasi…' : _position == null ? 'Ambil lokasi GPS' : 'Ambil ulang lokasi'),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Expanded(child: Text('Pengiriman', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
                    IconButton(onPressed: _ratesLoading ? null : _loadRates, tooltip: 'Muat ulang ongkir', icon: const Icon(Icons.refresh)),
                  ]),
                  if (_ratesLoading) const LinearProgressIndicator(),
                  if (!_ratesLoading && _rates.isEmpty)
                    const Text('Ambil GPS untuk meminta pilihan ongkir dari backend.', style: TextStyle(color: Colors.black54))
                  else
                    RadioGroup<int>(
                      groupValue: _selectedRateIndex,
                      onChanged: (value) => setState(() => _selectedRateIndex = value ?? 0),
                      child: Column(
                        children: [
                          for (var i = 0; i < _rates.length; i++)
                            if (_rates[i] is Map)
                              RadioListTile<int>(
                                value: i,
                                contentPadding: EdgeInsets.zero,
                                title: Text(((_rates[i] as Map)['service'] ?? (_rates[i] as Map)['courier'] ?? (_rates[i] as Map)['method'] ?? 'Pengiriman').toString()),
                                subtitle: Text('${(_rates[i] as Map)['etd'] ?? 'Estimasi mengikuti server'} · ${(_rates[i] as Map)['distance_km'] ?? '-'} km'),
                                secondary: Text(_checkoutRupiah((_rates[i] as Map)['cost'])),
                              ),
                        ],
                      ),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Pembayaran', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  if (_paymentMethods.isEmpty)
                    const Text('Metode pembayaran belum diberikan oleh backend. Checkout dinonaktifkan agar tidak membuat alur pembayaran fiktif.', style: TextStyle(color: Colors.black54))
                  else
                    RadioGroup<String>(
                      groupValue: _paymentMethod,
                      onChanged: (value) => setState(() => _paymentMethod = value),
                      child: Column(
                        children: [
                          for (final method in _paymentMethods)
                            RadioListTile<String>(
                              value: method,
                              contentPadding: EdgeInsets.zero,
                              title: Text(_paymentLabel(method)),
                              subtitle: Text(_paymentDescription(method)),
                            ),
                        ],
                      ),
                    ),
                ]),
              ),
            ),
            if (_options['can_checkout'] == false || _options['can_checkout']?.toString() == '0')
              const _CheckoutNotice(icon: Icons.info_outline, title: 'Checkout belum tersedia untuk akun ini', message: 'Periksa status verifikasi akun sesuai aturan PWA.'),
            if (_lastError != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(14)),
                child: Text(_lastError!, style: const TextStyle(color: Color(0xFFB00020))),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _submitting || items.isEmpty || _addresses.isEmpty || _paymentMethods.isEmpty ? null : _placeOrder,
              icon: _submitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.lock_outline_rounded),
              label: Text(_submitting ? 'Memproses pesanan…' : 'Buat pesanan dan lanjut pembayaran'),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Harga, ongkir, stok, kelayakan checkout, dan status pembayaran tetap diputuskan backend. Aplikasi tidak menganggap pembayaran berhasil tanpa konfirmasi server.',
                style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.4)),
            ),
          ],
        );
      },
    ),
  );
}

String _paymentLabel(String method) {
  switch (method.toLowerCase()) {
    case 'qris': return 'QRIS';
    case 'va': return 'Virtual Account';
    case 'cod': return 'Bayar di tempat (COD)';
    case 'saldo': return 'Saldo akun';
    case 'gateway': return 'Payment gateway';
    case 'transfer': return 'Transfer bank';
    default: return method.toUpperCase();
  }
}

String _paymentDescription(String method) {
  switch (method.toLowerCase()) {
    case 'qris': return 'QRIS Bank Jatim sesuai konfigurasi backend';
    case 'va': return 'Virtual Account Bank Jatim sesuai konfigurasi backend';
    case 'cod': return 'Pembayaran di lokasi saat pesanan diterima';
    case 'saldo': return 'Divalidasi server berdasarkan saldo akun';
    case 'gateway': return 'Diarahkan ke penyedia pembayaran sesuai konfigurasi server';
    case 'transfer': return 'Instruksi transfer mengikuti status pembayaran dari server';
    default: return 'Mengikuti ketentuan backend';
  }
}

class _OrderCreatedView extends StatelessWidget {
  const _OrderCreatedView({
    required this.order,
    required this.payment,
    required this.onContinuePayment,
    required this.onDone,
  });
  final Map<String, dynamic> order;
  final Map<String, dynamic> payment;
  final VoidCallback onContinuePayment;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final provider = (payment['provider'] ?? '').toString().toUpperCase();
    final pending = (payment['status'] ?? '').toString().toLowerCase().contains('pending') ||
        (payment['status'] ?? '').toString().toLowerCase().contains('waiting');
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.receipt_long_rounded, size: 64, color: Color(0xFFD20A2E)),
          const SizedBox(height: 16),
          const Text('Pesanan tercatat di server', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Nomor pesanan: ${order['code'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Total server: ${_checkoutRupiah(order['total'])}', style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 10),
          Text('Status pembayaran: ${payment['status'] ?? order['status'] ?? 'menunggu status server'}'),
          if (pending) const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Pembayaran belum dinyatakan berhasil. Ikuti status yang dikembalikan server.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
          ),
          const SizedBox(height: 20),
          if (provider == 'MOCK_BANK_JATIM')
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: onContinuePayment,
              icon: const Icon(Icons.open_in_browser_rounded),
              label: const Text('Lanjut ke halaman pembayaran Bank Jatim'),
            )),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: OutlinedButton(onPressed: onDone, child: const Text('Kembali ke belanja'))),
        ]),
      ),
    );
  }
}

class _CheckoutError extends StatelessWidget {
  const _CheckoutError({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(26),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_outlined, size: 48, color: Color(0xFFD20A2E)),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Coba lagi')),
      ]),
    ),
  );
}

class _CheckoutNotice extends StatelessWidget {
  const _CheckoutNotice({required this.icon, required this.title, required this.message});
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: const Color(0xFFD20A2E)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(message, style: const TextStyle(color: Colors.black54, height: 1.4)),
      ])),
    ]),
  );
}
