import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import 'service_selection_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.message, this.expectedRole});

  final String? message;
  final String? expectedRole;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  String? _localError;

  bool get _isDriver => widget.expectedRole == 'driver';

  void _clearVisibleError() {
    if (_localError != null) setState(() => _localError = null);
    ref.read(authControllerProvider.notifier).clearError();
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _localError = null);
    ref.read(authControllerProvider.notifier).clearError();
    await ref.read(authControllerProvider.notifier).login(
      _login.text.trim(),
      _password.text,
      'BersolekMart Android',
      expectedRole: widget.expectedRole,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final errorText = _localError ??
        (auth.hasError ? apiErrorMessage(auth.error!) : widget.message);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F2F3),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - 22).clamp(0.0, double.infinity).toDouble(),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: auth.isLoading
                              ? null
                              : () {
                                  ref.read(authControllerProvider.notifier).clearError();
                                  ref.read(selectedServiceProvider.notifier).select('choose');
                                },
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          label: const Text('Ganti layanan'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFFEFE5E7)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x0B32000D),
                              blurRadius: 28,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFE8EC),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Image.asset(
                                    'assets/branding/bersolek-mart-adaptive-foreground.png',
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, _, _) => const Icon(
                                      Icons.shopping_bag_rounded,
                                      color: Color(0xFFD20A2E),
                                      size: 32,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'BersolekMart',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: -0.4,
                                        ),
                                      ),
                                      SizedBox(height: 3),
                                      Text(
                                        'Marketplace UMKM lokal',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF0F2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _isDriver ? Icons.delivery_dining_rounded : Icons.shopping_bag_outlined,
                                    color: const Color(0xFFD20A2E),
                                    size: 19,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _isDriver ? 'LAYANAN DRIVER' : 'LAYANAN BELANJA',
                                    style: const TextStyle(
                                      color: Color(0xFFD20A2E),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.7,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 13),
                            Text(
                              _isDriver ? 'Masuk sebagai Driver' : 'Selamat datang kembali',
                              style: const TextStyle(
                                fontSize: 25,
                                height: 1.10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.7,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _isDriver
                                  ? 'Gunakan akun Driver BersolekMart untuk melihat pekerjaan pengantaran yang ditugaskan.'
                                  : 'Masuk untuk melihat produk UMKM lokal, mengelola keranjang, dan memantau pesanan.',
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.45,
                                color: Color(0xFF6B6265),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TextFormField(
                                    controller: _login,
                                    enabled: !auth.isLoading,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                    autofillHints: const [AutofillHints.username],
                                    onChanged: (_) => _clearVisibleError(),
                                    validator: (value) => value == null || value.trim().isEmpty
                                        ? 'Masukkan username atau email.'
                                        : null,
                                    decoration: const InputDecoration(
                                      labelText: 'Username atau email',
                                      hintText: 'Masukkan akun BersolekMart',
                                      prefixIcon: Icon(Icons.person_outline_rounded),
                                      filled: true,
                                    ),
                                  ),
                                  const SizedBox(height: 11),
                                  TextFormField(
                                    controller: _password,
                                    enabled: !auth.isLoading,
                                    obscureText: _obscure,
                                    textInputAction: TextInputAction.done,
                                    autofillHints: const [AutofillHints.password],
                                    onChanged: (_) => _clearVisibleError(),
                                    onFieldSubmitted: (_) => _submit(),
                                    validator: (value) => value == null || value.isEmpty
                                        ? 'Masukkan password.'
                                        : null,
                                    decoration: InputDecoration(
                                      labelText: 'Password',
                                      hintText: 'Masukkan password akun',
                                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                                      suffixIcon: IconButton(
                                        tooltip: _obscure ? 'Tampilkan password' : 'Sembunyikan password',
                                        onPressed: auth.isLoading
                                            ? null
                                            : () => setState(() => _obscure = !_obscure),
                                        icon: Icon(_obscure
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined),
                                      ),
                                      filled: true,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (errorText != null && errorText.trim().isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(13),
                                decoration: BoxDecoration(
                                  color: colorScheme.errorContainer,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: colorScheme.error.withAlpha(36)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.error_outline_rounded,
                                      color: colorScheme.onErrorContainer, size: 20),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Text(
                                        errorText,
                                        style: TextStyle(
                                          height: 1.35,
                                          color: colorScheme.onErrorContainer,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                ),
                                onPressed: auth.isLoading ? null : _submit,
                                icon: auth.isLoading
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.arrow_forward_rounded),
                                label: Text(
                                  auth.isLoading
                                      ? 'Menghubungkan ke server…'
                                      : _isDriver
                                          ? 'Masuk sebagai Driver'
                                          : 'Masuk dan Belanja',
                                ),
                              ),
                            ),
                            const SizedBox(height: 13),
                            const Divider(height: 1),
                            const SizedBox(height: 11),
                            Text(
                              _isDriver
                                  ? 'Khusus akun Driver. Akun Pembeli masuk melalui layanan Belanja.'
                                  : 'Khusus akun Pembeli. Driver masuk melalui layanan Driver.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Administrator, Operator, dan Merchant tetap menggunakan dashboard web.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: Color(0xFF82777A)),
                      ),
                    ],
                  ),
                ),
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
