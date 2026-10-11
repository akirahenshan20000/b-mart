import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import 'service_selection_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.message, this.expectedRole});

  final String? message;
  final String? expectedRole;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await ref.read(authControllerProvider.notifier).login(
      _login.text,
      _password.text,
      'BersolekMart Android',
      expectedRole: widget.expectedRole,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final errorText = auth.hasError ? '${auth.error}' : widget.message;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset('assets/branding/bersolek-mart-adaptive-foreground.png', width: 42, height: 42, fit: BoxFit.contain),
                          const SizedBox(width: 10),
                          const Text('BersolekMart', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 38),
                  Text(widget.expectedRole == 'driver' ? 'Masuk sebagai Driver' : widget.expectedRole == 'customer' ? 'Masuk untuk Belanja' : 'Selamat datang kembali', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, height: 1.05)),
                  const SizedBox(height: 8),
                  Text(widget.expectedRole == 'driver' ? 'Masuk menggunakan akun Driver BersolekMart untuk mengelola pengantaran.' : widget.expectedRole == 'customer' ? 'Masuk menggunakan akun pembeli untuk menemukan produk UMKM lokal.' : 'Masuk menggunakan akun BersolekMart.', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.black54)),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _login,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Username / Email', prefixIcon: Icon(Icons.person_outline), filled: true),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(onPressed: () => setState(() => _obscure = !_obscure), icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off)),
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (errorText != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer, borderRadius: BorderRadius.circular(14)),
                      child: Text(errorText, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
                    ),
                    const SizedBox(height: 14),
                  ],
                  FilledButton.icon(
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    onPressed: auth.isLoading ? null : _submit,
                    icon: auth.isLoading ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.arrow_forward_rounded),
                    label: Text(auth.isLoading ? 'Menghubungkan…' : widget.expectedRole == 'driver' ? 'Masuk sebagai Driver' : widget.expectedRole == 'customer' ? 'Masuk dan Belanja' : 'Masuk ke BersolekMart'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => ref.read(selectedServiceProvider.notifier).select('choose'),
                    child: const Text('Ganti layanan'),
                  ),
                  const SizedBox(height: 10),
                  Text(widget.expectedRole == 'driver' ? 'Khusus akun Driver. Akun Pembeli masuk melalui layanan Belanja.' : widget.expectedRole == 'customer' ? 'Khusus akun Pembeli. Driver masuk melalui layanan Driver.' : 'Administrator, Operator, dan Merchant tetap menggunakan web/backend.', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }
}