import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';

class AccountProfileEditPage extends ConsumerStatefulWidget {
  const AccountProfileEditPage({
    super.key,
    required this.title,
    required this.initialUser,
  });

  final String title;
  final Map<String, dynamic> initialUser;

  @override
  ConsumerState<AccountProfileEditPage> createState() => _AccountProfileEditPageState();
}

class _AccountProfileEditPageState extends ConsumerState<AccountProfileEditPage> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialUser['full_name']?.toString() ?? '');
    _phone = TextEditingController(text: widget.initialUser['phone']?.toString() ?? '');
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama lengkap minimal 2 karakter.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).post('/profile', {
        'full_name': _name.text.trim(),
        'phone': _phone.text.trim(),
      });
      ref.invalidate(authControllerProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil gagal disimpan. Pastikan API profil mobile sudah dipasang di server.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Perbarui informasi akun', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        const Text('Perubahan dikirim ke API akun BersolekMart.', style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 22),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nama lengkap', prefixIcon: Icon(Icons.person_outline_rounded)),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Nomor telepon', prefixIcon: Icon(Icons.phone_outlined)),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Menyimpan...' : 'Simpan perubahan'),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }
}
