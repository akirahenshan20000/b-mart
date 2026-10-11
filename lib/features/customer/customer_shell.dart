import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';

String formatRupiah(dynamic raw) {
  final value = raw is num ? raw.round() : int.tryParse(raw?.toString() ?? '') ?? double.tryParse(raw?.toString() ?? '')?.round() ?? 0;
  final digits = value.abs().toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write('.');
    grouped.write(digits[i]);
  }
  return 'Rp ${value < 0 ? '-' : ''}${grouped.toString()}';
}

List<dynamic> catalogProductsFromPayload(dynamic payload) {
  if (payload is! Map || payload['data'] is! List) return const [];
  return List<dynamic>.from(payload['data'] as List);
}

String resolveMediaUrl(String raw, String apiBase) {
  final value = raw.trim();
  if (value.isEmpty) return '';
  final parsed = Uri.tryParse(value);
  if (parsed != null && (parsed.scheme == 'http' || parsed.scheme == 'https')) return value;

  final apiUri = Uri.parse(apiBase);
  var prefixPath = apiUri.path.replaceFirst(RegExp(r'/api/v1/?$'), '');
  prefixPath = prefixPath.replaceFirst(RegExp(r'/$'), '');
  final base = apiUri.replace(path: prefixPath, query: null, fragment: null).toString().replaceFirst(RegExp(r'/$'), '');
  final relative = value.replaceFirst(RegExp(r'^/+'), '');
  return Uri.encodeFull('$base/$relative');
}

class CustomerShell extends ConsumerStatefulWidget {
  const CustomerShell({super.key});

  @override
  ConsumerState<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends ConsumerState<CustomerShell> {
  int _index = 0;
  String? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final pages = [
      CustomerHome(key: ValueKey('home-${_selectedCategory ?? 'all'}'), initialCategory: _selectedCategory),
      CustomerCategories(onSelect: (category) => setState(() {
        _selectedCategory = category;
        _index = 0;
      })),
      const CustomerOrders(),
      const CustomerProfile(),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF171113),
        elevation: 0,
        title: Row(
          children: [
            Image.asset('assets/branding/bersolek-mart-icon-512.png', width: 32, height: 32, fit: BoxFit.contain),
            const SizedBox(width: 8),
            const Text('BersolekMart', style: TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Belanja'),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: 'Kategori'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Pesanan'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Akun'),
        ],
      ),
    );
  }
}

class CustomerHome extends ConsumerStatefulWidget {
  const CustomerHome({super.key, this.initialCategory});
  final String? initialCategory;

  @override
  ConsumerState<CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends ConsumerState<CustomerHome> {
  late Future<Map<String, dynamic>> _future;
  final _search = TextEditingController();
  String? _category;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant CustomerHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCategory != widget.initialCategory) {
      _category = widget.initialCategory;
      _future = _load();
    }
  }

  Future<Map<String, dynamic>> _load() async {
    final api = ref.read(apiClientProvider);
    final query = <String, String>{'limit': '24'};
    if (_search.text.trim().isNotEmpty) query['q'] = _search.text.trim();
    if (_category != null && _category!.isNotEmpty) query['category'] = _category!;
    final results = await Future.wait([
      api.get('/catalog/products', query: query),
      api.get('/catalog/categories'),
      api.baseUrl(),
    ]);
    final productPayload = results[0] as Map;
    final categoryPayload = results[1] as Map;
    return {
      'products': catalogProductsFromPayload(productPayload),
      'categories': List<dynamic>.from(categoryPayload['data'] as List? ?? const []),
      'apiBase': results[2] as String,
    };
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorPanel(message: 'Katalog belum dapat dimuat. Periksa koneksi lalu coba lagi.', onRetry: _reload);
          }

          final data = snapshot.data ?? const <String, dynamic>{};
          final items = List<dynamic>.from(data['products'] as List? ?? const []);
          final categories = List<dynamic>.from(data['categories'] as List? ?? const []);
          final apiBase = data['apiBase']?.toString() ?? '';

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFD20A2E), Color(0xFFEF5368)]),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.location_on_rounded, color: Colors.white, size: 17),
                      SizedBox(width: 5),
                      Text('Kota Probolinggo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ]),
                    SizedBox(height: 12),
                    Text('UMKM Lokal, Pilihan Terbaik', style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w900)),
                    SizedBox(height: 5),
                    Text('Belanja produk lokal dan dukung usaha di sekitar kita.', style: TextStyle(color: Colors.white, height: 1.35)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _reload(),
                decoration: InputDecoration(
                  hintText: 'Cari produk, toko, atau kategori…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: _reload),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 22),
              Row(children: [
                const Expanded(child: Text('Kategori', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
                TextButton(onPressed: () => setState(() => _category = null), child: const Text('Semua')),
              ]),
              SizedBox(
                height: 94,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _CategoryTile(label: 'Semua', icon: Icons.apps_rounded, selected: _category == null, onTap: () {
                        _category = null;
                        _reload();
                      });
                    }
                    final category = Map<String, dynamic>.from(categories[index - 1] as Map);
                    final slug = (category['slug'] ?? '').toString();
                    return _CategoryTile(
                      label: (category['name'] ?? 'Kategori').toString().trim(),
                      icon: _categoryIcon((category['name'] ?? '').toString()),
                      selected: _category == slug,
                      onTap: () {
                        _category = slug;
                        _reload();
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 22),
              Row(children: [
                const Expanded(child: Text('Produk UMKM Lokal', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
                Text('${items.length} produk', style: const TextStyle(color: Colors.black54, fontSize: 12)),
              ]),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 38),
                  child: Column(children: [
                    Icon(Icons.inventory_2_outlined, size: 54, color: Color(0xFFB5AEB0)),
                    SizedBox(height: 10),
                    Text('Produk belum tersedia', style: TextStyle(fontWeight: FontWeight.w800)),
                    SizedBox(height: 4),
                    Text('Coba kata kunci atau kategori lain.', style: TextStyle(color: Colors.black54)),
                  ]),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, childAspectRatio: .60, crossAxisSpacing: 12, mainAxisSpacing: 12,
                  ),
                  itemBuilder: (context, index) {
                    final product = Map<String, dynamic>.from(items[index] as Map);
                    final basePrice = _number(product['price']);
                    final salePrice = _number(product['sale_price']);
                    final price = salePrice > 0 && basePrice > 0 && salePrice < basePrice ? salePrice : basePrice;
                    final image = (product['image'] ?? '').toString();
                    return InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => _showProduct(context, product, apiBase),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: ProductImageView(path: image, apiBase: apiBase)),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text((product['name'] ?? 'Produk').toString(), maxLines: 2, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w800, height: 1.2)),
                                  const SizedBox(height: 7),
                                  Text(formatRupiah(price), maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Color(0xFFD20A2E), fontWeight: FontWeight.w900, fontSize: 15)),
                                  const SizedBox(height: 5),
                                  Text((product['store_name'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11, color: Colors.black54)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }
}

class ProductImageView extends StatelessWidget {
  const ProductImageView({super.key, required this.path, required this.apiBase});
  final String path;
  final String apiBase;

  @override
  Widget build(BuildContext context) {
    final url = resolveMediaUrl(path, apiBase);
    if (url.isEmpty || url.toLowerCase().split('?').first.endsWith('.svg')) {
      return const _ImageFallback();
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      errorBuilder: (_, _, _) => const _ImageFallback(),
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : const _ImageFallback(loading: true),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback({this.loading = false});
  final bool loading;

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFFF4EEEE),
    alignment: Alignment.center,
    child: Icon(loading ? Icons.hourglass_top_rounded : Icons.image_not_supported_outlined,
      size: 42, color: const Color(0xFFB7AEB0)),
  );
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.label, required this.icon, required this.selected, required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 76,
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Column(children: [
        Container(
          width: 54, height: 54,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFFE4E8) : Colors.white,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: selected ? const Color(0xFFD20A2E) : const Color(0xFFECE4E5)),
          ),
          child: Icon(icon, color: const Color(0xFFD20A2E), size: 26),
        ),
        const SizedBox(height: 6),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w800 : FontWeight.w500)),
      ]),
    ),
  );
}

IconData _categoryIcon(String name) {
  final value = name.toLowerCase();
  if (value.contains('makan') || value.contains('kuliner') || value.contains('oleh')) return Icons.restaurant_rounded;
  if (value.contains('minum') || value.contains('kopi')) return Icons.local_cafe_rounded;
  if (value.contains('fashion') || value.contains('batik')) return Icons.checkroom_rounded;
  if (value.contains('sembako')) return Icons.shopping_basket_rounded;
  if (value.contains('kerajinan')) return Icons.handyman_rounded;
  return Icons.category_rounded;
}

double _number(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

void _showProduct(BuildContext context, Map<String, dynamic> product, String apiBase) {
  final base = _number(product['price']);
  final sale = _number(product['sale_price']);
  final price = sale > 0 && base > 0 && sale < base ? sale : base;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(height: 230, width: double.infinity,
                child: ProductImageView(path: (product['image'] ?? '').toString(), apiBase: apiBase)),
            ),
            const SizedBox(height: 16),
            Text((product['name'] ?? 'Produk').toString(), style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(formatRupiah(price), style: const TextStyle(fontSize: 22, color: Color(0xFFD20A2E), fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text((product['store_name'] ?? 'UMKM Lokal').toString(), style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 14),
            Text((product['description'] ?? 'Informasi produk belum tersedia.').toString(), style: const TextStyle(height: 1.45)),
            const SizedBox(height: 12),
            Text('Stok tersedia: ${product['stock'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 18),
            const Text('Pembelian dan pembayaran mengikuti alur yang tersedia pada layanan BersolekMart.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
      ),
    ),
  );
}

class CustomerCategories extends ConsumerStatefulWidget {
  const CustomerCategories({super.key, required this.onSelect});
  final ValueChanged<String> onSelect;

  @override
  ConsumerState<CustomerCategories> createState() => _CustomerCategoriesState();
}

class _CustomerCategoriesState extends ConsumerState<CustomerCategories> {
  late Future<List<dynamic>> _future;
  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<dynamic>> _load() async {
    final payload = await ref.read(apiClientProvider).get('/catalog/categories');
    return List<dynamic>.from(payload['data'] as List? ?? const []);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return _ErrorPanel(message: 'Kategori belum dapat dimuat.', onRetry: () => setState(() => _future = _load()));
      final items = snapshot.data ?? const [];
      if (items.isEmpty) return const Center(child: Text('Belum ada kategori aktif.'));
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Jelajahi Kategori', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text('Temukan produk berdasarkan jenisnya.', style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 16),
          ...items.map((raw) {
            final category = Map<String, dynamic>.from(raw as Map);
            final name = (category['name'] ?? 'Kategori').toString().trim();
            final slug = (category['slug'] ?? '').toString();
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  leading: Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(color: const Color(0xFFFFE4E8), borderRadius: BorderRadius.circular(14)),
                    child: Icon(_categoryIcon(name), color: const Color(0xFFD20A2E)),
                  ),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text('Lihat produk kategori ini'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: slug.isEmpty ? null : () => widget.onSelect(slug),
                ),
              ),
            );
          }),
        ],
      );
    },
  );
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
    return List<dynamic>.from(payload['data'] as List? ?? const []);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return _ErrorPanel(message: 'Pesanan belum dapat dimuat.', onRetry: () => setState(() => _future = _load()));
      final items = snapshot.data ?? const [];
      if (items.isEmpty) return ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
        SizedBox(height: 100), Icon(Icons.receipt_long_outlined, size: 54, color: Color(0xFFB7AEB0)),
        SizedBox(height: 12), Center(child: Text('Belum ada pesanan.')),
      ]);
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final order = Map<String, dynamic>.from(items[index] as Map);
          return Card(child: ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xFFFFE4E8), child: Icon(Icons.receipt_long, color: Color(0xFFD20A2E))),
            title: Text('${order['code'] ?? order['order_code'] ?? 'Pesanan'}', style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${order['flow_state'] ?? order['status'] ?? '-'}'),
            trailing: Text(formatRupiah(order['total']), style: const TextStyle(color: Color(0xFFD20A2E), fontWeight: FontWeight.w900)),
          ));
        },
      );
    },
  );
}

class CustomerProfile extends ConsumerWidget {
  const CustomerProfile({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final user = session?.user ?? const <String, dynamic>{};
    final name = user['full_name']?.toString() ?? 'Pengguna BersolekMart';
    return ListView(padding: const EdgeInsets.all(22), children: [
      const SizedBox(height: 12),
      Center(child: Image.asset('assets/branding/bersolek-mart-icon-512.png', width: 100, height: 100)),
      const SizedBox(height: 14),
      Center(child: Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
      Center(child: Text('${user['email'] ?? user['phone'] ?? '-'}', style: const TextStyle(color: Colors.black54))),
      const SizedBox(height: 26),
      Card(child: ListTile(leading: const Icon(Icons.person_outline), title: const Text('Profil Saya'), trailing: const Icon(Icons.chevron_right))),
      const SizedBox(height: 8),
      Card(child: ListTile(leading: const Icon(Icons.support_agent_outlined), title: const Text('Bantuan'), trailing: const Icon(Icons.chevron_right))),
      const SizedBox(height: 22),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFD20A2E), padding: const EdgeInsets.symmetric(vertical: 14)),
        onPressed: () => ref.read(authControllerProvider.notifier).logout(),
        icon: const Icon(Icons.logout_rounded), label: const Text('Keluar'),
      ),
    ]);
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_rounded, size: 54, color: Color(0xFFD20A2E)),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton(onPressed: onRetry, child: const Text('Coba Lagi')),
      ]),
    ),
  );
}
