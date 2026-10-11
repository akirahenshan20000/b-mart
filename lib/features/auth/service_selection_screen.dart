import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';


final selectedServiceProvider =
    NotifierProvider<SelectedServiceController, String?>(SelectedServiceController.new);

class SelectedServiceController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? value) => state = value;
}

class WelcomeSplashScreen extends ConsumerWidget {
  const WelcomeSplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFF17090D),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF12080B), Color(0xFF360610), Color(0xFF85001C)],
            stops: [0, .55, 1],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: (constraints.maxHeight - 44).clamp(0.0, double.infinity).toDouble()),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withAlpha(24)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.location_on_rounded, color: Color(0xFFFFC7D0), size: 15),
                            SizedBox(width: 5),
                            Text('PROBOLINGGO, JAWA TIMUR',
                              style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: .8)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 34),
                    Container(
                      width: 154,
                      height: 154,
                      padding: const EdgeInsets.all(21),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(10),
                        borderRadius: BorderRadius.circular(42),
                        border: Border.all(color: Colors.white.withAlpha(26)),
                        boxShadow: const [
                          BoxShadow(color: Color(0x44000000), blurRadius: 34, offset: Offset(0, 14)),
                        ],
                      ),
                      child: Image.asset(
                        'assets/branding/bersolek-mart-adaptive-foreground.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Icon(Icons.shopping_bag_rounded, size: 86, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 26),
                    const Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: 'Bersolek', style: TextStyle(color: Colors.white)),
                          TextSpan(text: 'Mart', style: TextStyle(color: Color(0xFFFF405D))),
                        ],
                      ),
                      style: TextStyle(fontSize: 38, height: 1, fontWeight: FontWeight.w900, letterSpacing: -1.2),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Marketplace lokal, peluang tanpa batas.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700, height: 1.3),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Dari kita, untuk semua. UMKM maju, Probolinggo Bersolek.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    const Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _WelcomeFeature(icon: Icons.storefront_rounded, label: 'UMKM lokal'),
                        _WelcomeFeature(icon: Icons.verified_user_outlined, label: 'Transaksi aman'),
                        _WelcomeFeature(icon: Icons.delivery_dining_rounded, label: 'Pengantaran'),
                      ],
                    ),
                    const SizedBox(height: 36),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF8A001D),
                          padding: const EdgeInsets.symmetric(vertical: 17),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
                          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                        onPressed: () => ref.read(selectedServiceProvider.notifier).select('choose'),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Mulai sekarang'),
                            SizedBox(width: 9),
                            Icon(Icons.arrow_forward_rounded, size: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    const Text('Belanja lokal. Dukung usaha di sekitar kita.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeFeature extends StatelessWidget {
  const _WelcomeFeature({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withAlpha(12),
      border: Border.all(color: Colors.white.withAlpha(22)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color(0xFFFFA3B2), size: 15),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

class ServiceSelectionScreen extends ConsumerWidget {
  const ServiceSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F4F4),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF211216), Color(0xFF7E001A), Color(0xFFD20A2E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white.withAlpha(20), borderRadius: BorderRadius.circular(17)),
                      child: Image.asset(
                        'assets/branding/bersolek-mart-adaptive-foreground.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Icon(Icons.shopping_bag_rounded, color: Colors.white, size: 36),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('BersolekMart', style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: -.6)),
                          SizedBox(height: 5),
                          Text('Satu aplikasi, dua layanan.',
                            style: TextStyle(color: Colors.white70, height: 1.35, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              const Text('Pilih layanan', style: TextStyle(fontSize: 28, height: 1.08, fontWeight: FontWeight.w900, letterSpacing: -.7, color: Color(0xFF171113))),
              const SizedBox(height: 7),
              const Text('Pilih sesuai kebutuhanmu. Akun dan akses tetap ditentukan oleh server.',
                style: TextStyle(color: Color(0xFF6B6265), height: 1.45, fontSize: 13)),
              const SizedBox(height: 20),
              _ServiceCard(
                icon: Icons.shopping_bag_rounded,
                title: 'Belanja',
                subtitle: 'Jelajahi produk UMKM, atur keranjang, dan pantau pesanan.',
                accent: const Color(0xFFD20A2E),
                tag: 'UNTUK PEMBELI',
                onTap: () {
                  ref.read(authControllerProvider.notifier).clearError();
                  ref.read(selectedServiceProvider.notifier).select('customer');
                },
              ),
              const SizedBox(height: 13),
              _ServiceCard(
                icon: Icons.delivery_dining_rounded,
                title: 'Driver',
                subtitle: 'Kelola penugasan, navigasi, dan proses pengantaran.',
                accent: const Color(0xFF171113),
                tag: 'UNTUK KURIR',
                onTap: () {
                  ref.read(authControllerProvider.notifier).clearError();
                  ref.read(selectedServiceProvider.notifier).select('driver');
                },
              ),
              const SizedBox(height: 22),
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    ref.read(authControllerProvider.notifier).clearError();
                    ref.read(selectedServiceProvider.notifier).select(null);
                  },
                  icon: const Icon(Icons.arrow_back_rounded, size: 17),
                  label: const Text('Kembali ke halaman awal'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.tag,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final String tag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFEDE4E6)),
            boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 18, offset: Offset(0, 7))],
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: accent.withAlpha(15),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, size: 31, color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tag, style: TextStyle(fontSize: 9, letterSpacing: .8, color: accent, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(title, style: const TextStyle(fontSize: 21, height: 1.1, fontWeight: FontWeight.w900, color: Color(0xFF171113))),
                    const SizedBox(height: 5),
                    Text(subtitle, style: const TextStyle(color: Color(0xFF6B6265), fontSize: 12, height: 1.4)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 17),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
