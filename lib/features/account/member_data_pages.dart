import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';

const _areas = <String, List<String>>{
  'Kademangan': ['Kademangan', 'Ketapang', 'Pilang', 'Pohsangit Kidul', 'Triwung Kidul', 'Triwung Lor'],
  'Kanigaran': ['Curahgrinting', 'Kanigaran', 'Kebonsari Kulon', 'Kebonsari Wetan', 'Sukoharjo', 'Tisnonegaran'],
  'Kedopok': ['Jrebeng Kulon', 'Jrebeng Lor', 'Jrebeng Wetan', 'Kareng Lor', 'Kedopok', 'Sumber Wetan'],
  'Mayangan': ['Jati', 'Mayangan', 'Mangunharjo', 'Sukabumi', 'Wiroborang'],
  'Wonoasih': ['Jrebeng Kidul', 'Kedung Asem', 'Kedung Galeng', 'Pakistaji', 'Sumber Taman', 'Wonoasih'],
};

List<dynamic> _payloadList(dynamic payload) =>
    payload is Map && payload['data'] is List
        ? List<dynamic>.from(payload['data'] as List)
        : <dynamic>[];

class MemberAddressBookPage extends ConsumerStatefulWidget {
  const MemberAddressBookPage({super.key, this.title = 'Alamat Pengiriman'});

  final String title;

  @override
  ConsumerState<MemberAddressBookPage> createState() => _MemberAddressBookPageState();
}

class _MemberAddressBookPageState extends ConsumerState<MemberAddressBookPage> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<dynamic>> _load() async =>
      _payloadList(await ref.read(apiClientProvider).get('/addresses'));

  Future<void> _edit([Map<String, dynamic>? address]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => MemberAddressEditorPage(initial: address)),
    );
    if (!mounted) return;
    if (saved == true) {
      setState(() => _future = _load());
    }
  }

  Future<void> _delete(Map<String, dynamic> address) async {
    final id = int.tryParse(address['id']?.toString() ?? '') ?? 0;
    if (id < 1) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus alamat?'),
        content: Text('Alamat “${address['label'] ?? 'Alamat'}” akan dihapus dari akun ini.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(apiClientProvider).post('/addresses/delete/$id', <String, dynamic>{});
      if (mounted) setState(() => _future = _load());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error is ApiException ? apiErrorMessage(error) : 'Alamat gagal dihapus. Coba lagi.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [IconButton(tooltip: 'Tambah alamat', onPressed: () => _edit(), icon: const Icon(Icons.add_location_alt_outlined))],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _edit(),
      icon: const Icon(Icons.add),
      label: const Text('Tambah alamat'),
    ),
    body: FutureBuilder<List<dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _RetryPanel(
            message: 'Alamat belum dapat dimuat dari server.',
            onRetry: () => setState(() => _future = _load()),
          );
        }
        final addresses = snapshot.data ?? const [];
        if (addresses.isEmpty) {
          return const _EmptyPanel(
            icon: Icons.location_on_outlined,
            title: 'Belum ada alamat',
            message: 'Tambahkan alamat dan pilih kecamatan serta kelurahan yang sesuai.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          itemCount: addresses.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final item = Map<String, dynamic>.from(addresses[index] as Map);
            final isDefault = item['is_default'] == true || item['is_default']?.toString() == '1';
            final subtitle = [
              item['recipient_name'], item['phone'], item['address_line'],
              item['village'], item['district'], item['city'],
            ].where((v) => v != null && v.toString().trim().isNotEmpty).join('\n');
            return Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(14),
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFFE5E9),
                  child: Icon(Icons.location_on_outlined, color: Color(0xFFD20A2E)),
                ),
                title: Row(children: [
                  Expanded(child: Text((item['label'] ?? 'Alamat').toString(), style: const TextStyle(fontWeight: FontWeight.w900))),
                  if (isDefault) const Chip(label: Text('Utama'), visualDensity: VisualDensity.compact),
                ]),
                subtitle: Padding(padding: const EdgeInsets.only(top: 6), child: Text(subtitle)),
                isThreeLine: true,
                onTap: () => _edit(item),
                trailing: PopupMenuButton<String>(
                  onSelected: (choice) {
                    if (choice == 'edit') _edit(item);
                    if (choice == 'delete') _delete(item);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit alamat')),
                    PopupMenuItem(value: 'delete', child: Text('Hapus alamat')),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  );
}

class MemberAddressEditorPage extends ConsumerStatefulWidget {
  const MemberAddressEditorPage({super.key, this.initial});
  final Map<String, dynamic>? initial;

  @override
  ConsumerState<MemberAddressEditorPage> createState() => _MemberAddressEditorPageState();
}

class _MemberAddressEditorPageState extends ConsumerState<MemberAddressEditorPage> {
  late final TextEditingController _label;
  late final TextEditingController _recipient;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _postalCode;
  String? _district;
  String? _village;
  double? _latitude;
  double? _longitude;
  double? _accuracy;
  bool _isDefault = false;
  bool _saving = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial ?? const <String, dynamic>{};
    _label = TextEditingController(text: initial['label']?.toString() ?? 'Rumah');
    _recipient = TextEditingController(text: initial['recipient_name']?.toString() ?? '');
    _phone = TextEditingController(text: initial['phone']?.toString() ?? '');
    _address = TextEditingController(text: initial['address_line']?.toString() ?? '');
    _postalCode = TextEditingController(text: initial['postal_code']?.toString() ?? '');
    final district = initial['district']?.toString();
    _district = _areas.containsKey(district) ? district : null;
    final village = initial['village']?.toString();
    _village = _district != null && _areas[_district]!.contains(village) ? village : null;
    _latitude = double.tryParse(initial['latitude']?.toString() ?? '');
    _longitude = double.tryParse(initial['longitude']?.toString() ?? '');
    _accuracy = double.tryParse(initial['accuracy_m']?.toString() ?? '');
    _isDefault = initial['is_default'] == true || initial['is_default']?.toString() == '1';
  }

  Future<void> _captureLocation() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw StateError('Izin lokasi ditolak. Alamat tetap dapat disimpan tanpa koordinat.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
      );
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _accuracy = position.accuracy;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lokasi didapat. Akurasi ${position.accuracy.toStringAsFixed(0)} m.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error is StateError ? error.message : 'GPS gagal didapat. Periksa izin dan sinyal lokasi.')),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    if (_label.text.trim().length < 2 || _recipient.text.trim().length < 2 ||
        _phone.text.trim().length < 8 || _address.text.trim().length < 8 ||
        _district == null || _village == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lengkapi label, penerima, nomor telepon, alamat, kecamatan dan kelurahan.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).post('/addresses/save', {
        if (widget.initial?['id'] != null) 'id': int.tryParse(widget.initial!['id'].toString()),
        'label': _label.text.trim(),
        'recipient_name': _recipient.text.trim(),
        'phone': _phone.text.trim(),
        'address_line': _address.text.trim(),
        'province': 'Jawa Timur',
        'city': 'Kota Probolinggo',
        'district': _district,
        'village': _village,
        'postal_code': _postalCode.text.trim(),
        'is_default': _isDefault ? 1 : 0,
        'latitude': _latitude,
        'longitude': _longitude,
        'accuracy_m': _accuracy,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alamat gagal disimpan. Periksa data dan koneksi API.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.initial == null ? 'Tambah alamat' : 'Edit alamat')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
      children: [
        TextField(controller: _label, decoration: const InputDecoration(labelText: 'Label alamat', hintText: 'Rumah atau Kantor')),
        const SizedBox(height: 12),
        TextField(controller: _recipient, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Nama penerima')),
        const SizedBox(height: 12),
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Nomor telepon')),
        const SizedBox(height: 12),
        TextField(controller: _address, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Alamat lengkap', alignLabelWithHint: true)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _district,
          decoration: const InputDecoration(labelText: 'Kecamatan'),
          items: _areas.keys.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          onChanged: (value) => setState(() {
            _district = value;
            _village = null;
          }),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _village,
          decoration: const InputDecoration(labelText: 'Kelurahan'),
          items: (_areas[_district] ?? const <String>[]).map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          onChanged: _district == null ? null : (value) => setState(() => _village = value),
        ),
        const SizedBox(height: 12),
        TextField(controller: _postalCode, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Kode pos (opsional)')),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _locating ? null : _captureLocation,
          icon: _locating
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.my_location_rounded),
          label: Text(_locating ? 'Mencari GPS…' : 'Ambil koordinat GPS'),
        ),
        if (_latitude != null && _longitude != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Koordinat tersimpan: ${_latitude!.toStringAsFixed(6)}, ${_longitude!.toStringAsFixed(6)} · akurasi ${(_accuracy ?? 0).toStringAsFixed(0)} m',
              style: const TextStyle(color: Colors.black54, fontSize: 12)),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _isDefault,
          onChanged: (value) => setState(() => _isDefault = value),
          title: const Text('Jadikan alamat utama'),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Menyimpan…' : 'Simpan alamat'),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    _label.dispose();
    _recipient.dispose();
    _phone.dispose();
    _address.dispose();
    _postalCode.dispose();
    super.dispose();
  }
}

class BankAccountsPage extends ConsumerStatefulWidget {
  const BankAccountsPage({super.key, this.title = 'Rekening'});
  final String title;

  @override
  ConsumerState<BankAccountsPage> createState() => _BankAccountsPageState();
}

class _BankAccountsPageState extends ConsumerState<BankAccountsPage> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<dynamic>> _load() async => _payloadList(await ref.read(apiClientProvider).get('/banks'));

  Future<void> _edit([Map<String, dynamic>? account]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => BankAccountEditorPage(initial: account)),
    );
    if (mounted && saved == true) setState(() => _future = _load());
  }

  Future<void> _delete(Map<String, dynamic> account) async {
    final id = int.tryParse(account['id']?.toString() ?? '') ?? 0;
    if (id < 1) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus rekening?'),
        content: const Text('Rekening ini akan dihapus dari akun.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(apiClientProvider).post('/banks/delete/$id', <String, dynamic>{});
      if (mounted) setState(() => _future = _load());
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rekening gagal dihapus.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [IconButton(tooltip: 'Tambah rekening', onPressed: () => _edit(), icon: const Icon(Icons.add))],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _edit(),
      icon: const Icon(Icons.add),
      label: const Text('Tambah rekening'),
    ),
    body: FutureBuilder<List<dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) {
          return _RetryPanel(
            message: 'Rekening belum dapat dimuat dari server.',
            onRetry: () => setState(() => _future = _load()),
          );
        }
        final accounts = snapshot.data ?? const [];
        if (accounts.isEmpty) {
          return const _EmptyPanel(
            icon: Icons.account_balance_outlined,
            title: 'Belum ada rekening',
            message: 'Tambahkan rekening untuk melengkapi informasi akun. Nomor rekening hanya ditampilkan sebagian.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          itemCount: accounts.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final item = Map<String, dynamic>.from(accounts[index] as Map);
            final number = (item['account_number'] ?? '').toString();
            final digits = number.replaceAll(RegExp(r'[^0-9]'), '');
            final masked = digits.length > 4 ? '•••• ${digits.substring(digits.length - 4)}' : '••••';
            final isDefault = item['is_default'] == true || item['is_default']?.toString() == '1';
            return Card(
              child: ListTile(
                leading: const CircleAvatar(backgroundColor: Color(0xFFFFE5E9), child: Icon(Icons.account_balance_outlined, color: Color(0xFFD20A2E))),
                title: Row(children: [
                  Expanded(child: Text((item['bank_name'] ?? 'Bank').toString(), style: const TextStyle(fontWeight: FontWeight.w900))),
                  if (isDefault) const Chip(label: Text('Utama'), visualDensity: VisualDensity.compact),
                ]),
                subtitle: Text('${item['account_name'] ?? 'Pemilik rekening'}\n$masked'),
                onTap: () => _edit(item),
                trailing: PopupMenuButton<String>(
                  onSelected: (choice) {
                    if (choice == 'edit') _edit(item);
                    if (choice == 'delete') _delete(item);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit rekening')),
                    PopupMenuItem(value: 'delete', child: Text('Hapus rekening')),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  );
}

class BankAccountEditorPage extends ConsumerStatefulWidget {
  const BankAccountEditorPage({super.key, this.initial});
  final Map<String, dynamic>? initial;

  @override
  ConsumerState<BankAccountEditorPage> createState() => _BankAccountEditorPageState();
}

class _BankAccountEditorPageState extends ConsumerState<BankAccountEditorPage> {
  late final TextEditingController _bank;
  late final TextEditingController _name;
  late final TextEditingController _number;
  bool _isDefault = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial ?? const <String, dynamic>{};
    _bank = TextEditingController(text: initial['bank_name']?.toString() ?? '');
    _name = TextEditingController(text: initial['account_name']?.toString() ?? '');
    _number = TextEditingController(text: initial['account_number']?.toString() ?? '');
    _isDefault = initial['is_default'] == true || initial['is_default']?.toString() == '1';
  }

  Future<void> _save() async {
    if (_bank.text.trim().length < 2 || _name.text.trim().length < 2 || _number.text.trim().length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lengkapi nama bank, nama pemilik, dan nomor rekening.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).post('/banks/save', {
        if (widget.initial?['id'] != null) 'id': int.tryParse(widget.initial!['id'].toString()),
        'bank_name': _bank.text.trim(),
        'account_name': _name.text.trim(),
        'account_number': _number.text.trim(),
        'is_default': _isDefault ? 1 : 0,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rekening gagal disimpan. Periksa data dan koneksi API.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.initial == null ? 'Tambah rekening' : 'Edit rekening')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(controller: _bank, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Nama bank')),
        const SizedBox(height: 12),
        TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Nama pemilik rekening')),
        const SizedBox(height: 12),
        TextField(controller: _number, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Nomor rekening')),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: _isDefault, onChanged: (value) => setState(() => _isDefault = value), title: const Text('Jadikan rekening utama')),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Menyimpan…' : 'Simpan rekening'),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    _bank.dispose();
    _name.dispose();
    _number.dispose();
    super.dispose();
  }
}

class _RetryPanel extends StatelessWidget {
  const _RetryPanel({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(26),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_outlined, size: 46, color: Color(0xFFD20A2E)),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Coba lagi')),
      ]),
    ),
  );
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.icon, required this.title, required this.message});
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 52, color: const Color(0xFFD20A2E)),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        const SizedBox(height: 6),
        Text(message, textAlign: TextAlign.center),
      ]),
    ),
  );
}
