import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Color(0xFFFFEEEE), Color(0xFFD20A2E)],
            stops: [0, .68, 1],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
            child: Column(
              children: [
                const Spacer(),
                Image.asset(
                  'assets/branding/bersolek-mart-icon-512.png',
                  width: 220,
                  height: 220,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.shopping_bag_rounded,
                    size: 120,
                    color: Color(0xFFD20A2E),
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'BersolekMart',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Color(0xFF171113)),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Marketplace Lokal, Peluang Tanpa Batas',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Color(0xFF555052)),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD20A2E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 17),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => ref.read(selectedServiceProvider.notifier).select('choose'),
                    child: const Text('Mulai', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Dari Kita, Untuk Semua. UMKM Maju, Probolinggo Bersolek.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ServiceSelectionScreen extends ConsumerWidget {
  const ServiceSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF171113),
        elevation: 0,
        title: const Text('Pilih Layanan', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            const SizedBox(height: 12),
            const Text('Halo, Selamat Datang!',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF171113))),
            const SizedBox(height: 8),
            const Text('Pilih layanan untuk melanjutkan menggunakan BersolekMart.',
              style: TextStyle(color: Color(0xFF686064), height: 1.4)),
            const SizedBox(height: 26),
            _ServiceCard(
              icon: Icons.shopping_bag_rounded,
              title: 'Belanja',
              subtitle: 'Temukan produk UMKM lokal dan pantau pesananmu.',
              onTap: () {
                ref.read(selectedServiceProvider.notifier).select('customer');
                // Root app switches to the role-specific login screen.
              },
            ),
            const SizedBox(height: 16),
            _ServiceCard(
              icon: Icons.delivery_dining_rounded,
              title: 'Driver',
              subtitle: 'Antar pesanan, kelola pengantaran, dan pantau pendapatan.',
              onTap: () {
                ref.read(selectedServiceProvider.notifier).select('driver');
                // Root app switches to the role-specific login screen.
              },
            ),
            const SizedBox(height: 26),
            Center(
              child: TextButton(
                onPressed: () => ref.read(selectedServiceProvider.notifier).select(null),
                child: const Text('Kembali ke halaman awal'),
              ),
            ),
          ],
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
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
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
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFF1DADD)),
            boxShadow: const [BoxShadow(color: Color(0x0C000000), blurRadius: 18, offset: Offset(0, 7))],
          ),
          child: Row(
            children: [
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(color: const Color(0xFFFFE8EB), borderRadius: BorderRadius.circular(18)),
                child: Icon(icon, size: 34, color: const Color(0xFFD20A2E)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 5),
                    Text(subtitle, style: const TextStyle(color: Color(0xFF686064), height: 1.35)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFFD20A2E), size: 28),
            ],
          ),
        ),
      ),
    );
  }
}
