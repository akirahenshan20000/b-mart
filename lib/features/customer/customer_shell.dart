import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';

class CustomerShell extends ConsumerStatefulWidget {
  const CustomerShell({super.key});

  @override
  ConsumerState<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends ConsumerState<CustomerShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = const [
      CustomerHome(),
      CustomerOrders(),
      CustomerProfile(),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('BersolekMart')),
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Belanja'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Pesanan'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }
}

class CustomerHome extends ConsumerStatefulWidget {
  const CustomerHome({super.key});
  @override
  ConsumerState<CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends ConsumerState<CustomerHome> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<dynamic>> _load() async {
    final payload = await ref.read(apiClientProvider).get('/catalog/products', query: {'limit': '24'});
    return List<dynamic>.from(payload['data'] as List);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => setState(() => _future = _load()),
      child: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return _ErrorPanel(message: '${snapshot.error}', onRetry: () => setState(() => _future = _load()));
          final items = snapshot.data ?? const [];
          if (items.isEmpty) return ListView(children: const [SizedBox(height: 140), Center(child: Text('Belum ada produk aktif.'))]);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _HeroCard(),
              const SizedBox(height: 18),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: .72, crossAxisSpacing: 12, mainAxisSpacing: 12),
                itemBuilder: (context, index) {
                  final p = Map<String, dynamic>.from(items[index] as Map);
                  final price = p['sale_price'] ?? p['price'];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(
                        child: Container(
                          color: const Color(0xFFEFF4F2),
                          alignment: Alignment.center,
                          child: const Icon(Icons.image_outlined, size: 48, color: Colors.black26),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${p['name'] ?? '-'}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text('Rp ${price ?? '-'}', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text('${p['store_name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                        ]),
                      ),
                    ]),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primaryContainer]), borderRadius: BorderRadius.circular(24)),
      child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Belanja UMKM Lokal', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
        SizedBox(height: 6),
        Text('Produk yang tampil berasal langsung dari API BersolekMart.', style: TextStyle(color: Colors.white70)),
      ]),
    );
  }
}

class CustomerOrders extends ConsumerStatefulWidget {
  const CustomerOrders({super.key});
  @override
  ConsumerState<CustomerOrders> createState() => _CustomerOrdersState();
}

class _CustomerOrdersState extends ConsumerState<CustomerOrders> {
  late Future<List<dynamic>> _future;
  @override
  void initState() { super.initState(); _future = _load(); }
  Future<List<dynamic>> _load() async {
    final payload = await ref.read(apiClientProvider).get('/orders');
    return List<dynamic>.from(payload['data'] as List);
  }
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return _ErrorPanel(message: '${snapshot.error}', onRetry: () => setState(() => _future = _load()));
        final items = snapshot.data ?? const [];
        if (items.isEmpty) return const Center(child: Text('Belum ada pesanan.'));
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final order = Map<String, dynamic>.from(items[index] as Map);
            return Card(child: ListTile(leading: CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primaryContainer, child: const Icon(Icons.receipt_long)), title: Text('${order['code']}'), subtitle: Text('${order['flow_state'] ?? order['status']} • Rp ${order['total']}'), trailing: const Icon(Icons.chevron_right)));
          },
        );
      },
    );
  }
}

class CustomerProfile extends ConsumerWidget {
  const CustomerProfile({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).valueOrNull;
    final user = session?.user ?? const <String, dynamic>{};
    return ListView(padding: const EdgeInsets.all(16), children: [
      CircleAvatar(radius: 40, child: Text('${(user['full_name'] ?? 'M').toString().substring(0, 1).toUpperCase()}')),
      const SizedBox(height: 14),
      Center(child: Text('${user['full_name'] ?? '-'}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
      Center(child: Text('${user['email'] ?? '-'}', style: const TextStyle(color: Colors.black54))),
      const SizedBox(height: 24),
      FilledButton.tonalIcon(onPressed: () => ref.read(authControllerProvider.notifier).logout(), icon: const Icon(Icons.logout), label: const Text('Keluar')),
    ]);
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud_off, size: 54), const SizedBox(height: 12), Text(message, textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton(onPressed: onRetry, child: const Text('Coba Lagi'))])));
}
