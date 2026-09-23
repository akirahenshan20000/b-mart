import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.message});

  final String? message;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _login = TextEditingController();
  final _password = TextEditingController();
  final _baseUrl = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _loadBaseUrl();
  }

  Future<void> _loadBaseUrl() async {
    final value = await ref.read(apiClientProvider).baseUrl();
    if (mounted) _baseUrl.text = value;
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final base = _baseUrl.text.trim();
    if (base.isEmpty) return;
    await ref.read(apiClientProvider).saveBaseUrl(base);
    await ref.read(authControllerProvider.notifier).login(
          _login.text,
          _password.text,
          'BersolekMart Debug Android',
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
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Image.asset('assets/branding/bersolek-mart-icon-512.png', width: 92, height: 92),
                  ),
                  const SizedBox(height: 16),
                  const Text('BersolekMart', textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text('Satu APK untuk Customer dan Driver', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 28),
                  TextField(controller: _login, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Username / Email', prefixIcon: Icon(Icons.person_outline))),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(onPressed: () => setState(() => _obscure = !_obscure), icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off))),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _baseUrl,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(labelText: 'API Base URL', prefixIcon: Icon(Icons.cloud_outlined), helperText: 'Emulator: http://10.0.2.2/bersolekmart/api/v1\nHP fisik: gunakan IP LAN PC.'),
                  ),
                  const SizedBox(height: 18),
                  if (errorText != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer, borderRadius: BorderRadius.circular(14)),
                      child: Text(errorText, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
                    ),
                    const SizedBox(height: 14),
                  ],
                  FilledButton.icon(
                    onPressed: auth.isLoading ? null : _submit,
                    icon: auth.isLoading ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login),
                    label: Text(auth.isLoading ? 'Menghubungkan…' : 'Masuk'),
                  ),
                  const SizedBox(height: 18),
                  const Text('Administrator, Operator, dan Merchant tidak tersedia di aplikasi mobile.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54)),
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
    _baseUrl.dispose();
    super.dispose();
  }
}
