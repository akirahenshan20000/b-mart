import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_controller.dart';
import '../account/account_profile_edit_page.dart';

/// Converts API values to readable UI text instead of exposing Map/List dumps.
String readableApiValue(dynamic value, {String fallback = '-'}) {
  if (value == null) return fallback;
  if (value is Map) {
    for (final key in const [
      'address_line', 'full_address', 'formatted_address', 'address',
      'label', 'name', 'full_name', 'recipient_name', 'title',
      'status_label', 'status_name', 'status', 'value', 'text',
      'phone', 'email',
    ]) {
      final candidate = value[key];
      if (candidate != null && candidate is! Map && candidate is! List) {
        final text = candidate.toString().trim();
        if (text.isNotEmpty) return text;
      }
    }
    return fallback;
  }
  if (value is List) {
    final parts = value
        .map((item) => readableApiValue(item, fallback: ''))
        .where((item) => item.isNotEmpty)
        .toList();
    return parts.isEmpty ? fallback : parts.join(', ');
  }
  final text = value.toString().trim();
  if (text.isEmpty) return fallback;
  if ((text.startsWith('{') && text.endsWith('}')) ||
      (text.startsWith('[') && text.endsWith(']'))) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map || decoded is List) {
        return readableApiValue(decoded, fallback: fallback);
      }
    } catch (_) {
      return fallback;
    }
  }
  return text;
}

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
  int _cartRevision = 0;
  String? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final pages = [
      CustomerHome(key: ValueKey('home-${_selectedCategory ?? 'all'}'), initialCategory: _selectedCategory, onOpenCart: () => setState(() { _cartRevision++; _index = 2; })),
      CustomerCategories(onSelect: (category) => setState(() {
        _selectedCategory = category;
        _index = 0;
      })),
      CustomerCart(key: ValueKey('cart-$_cartRevision')),
      const CustomerOrders(),
      const CustomerProfile(),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFD20A2E),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Image.asset('assets/branding/bersolek-mart-adaptive-foreground.png', width: 38, height: 38, fit: BoxFit.contain),
            const SizedBox(width: 8),
            const Text('BersolekMart', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -.3)),
          ],
        ),
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() { if (value == 2) _cartRevision++; _index = value; }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Belanja'),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: 'Kategori'),
          NavigationDestination(icon: Icon(Icons.shopping_basket_outlined), selectedIcon: Icon(Icons.shopping_basket), label: 'Keranjang'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Pesanan'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Akun'),
        ],
      ),
    );
  }
}

class CustomerHome extends ConsumerStatefulWidget {
  const CustomerHome({super.key, this.initialCategory, this.onOpenCart});
  final String? initialCategory;
  final VoidCallback? onOpenCart;

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

  Future<bool> _addToCart(Map<String, dynamic> product) async {
    final id = int.tryParse(product['id']?.toString() ?? '') ?? 0;
    if (id < 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Produk ini tidak memiliki ID yang valid.')));
      return false;
    }
    try {
      await ref.read(apiClientProvider).post('/cart/items', {'product_id': id, 'qty': 1});
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Produk ditambahkan ke keranjang.')));
      widget.onOpenCart?.call();
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal menambahkan produk. Pastikan API keranjang tersedia dan stok masih ada.')));
      }
      return false;
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
      api.get('/cms/home').catchError((_) => <String, dynamic>{}),
    ]);
    final productPayload = results[0] as Map;
    final categoryPayload = results[1] as Map;
    final cmsPayload = results[3] is Map ? results[3] as Map : const <String, dynamic>{};
    final cmsData = cmsPayload['data'] is Map ? cmsPayload['data'] as Map : cmsPayload;
    final slidesRaw = cmsData['hero_slides'] is List
        ? cmsData['hero_slides'] as List
        : cmsData['hero'] is Map
            ? [cmsData['hero']]
            : const <dynamic>[];
    return {
      'products': catalogProductsFromPayload(productPayload),
      'categories': List<dynamic>.from(categoryPayload['data'] as List? ?? const []),
      'heroSlides': slidesRaw.whereType<Map>().map((slide) => Map<String, dynamic>.from(slide)).where((slide) {
        final path = (slide['image_path'] ?? slide['image'] ?? '').toString().trim();
        return path.isNotEmpty;
      }).toList(),
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
          final heroSlides = List<dynamic>.from(data['heroSlides'] as List? ?? const []);

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              if (heroSlides.isNotEmpty)
                CustomerHeroSlider(slides: heroSlides, apiBase: apiBase)
              else
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFECE1E3))),
                  child: const Row(children: [
                    Icon(Icons.campaign_outlined, color: Color(0xFFD20A2E), size: 30),
                    SizedBox(width: 12),
                    Expanded(child: Text('Banner promosi belum tersedia. Produk UMKM tetap dapat dijelajahi di bawah ini.', style: TextStyle(fontWeight: FontWeight.w600, height: 1.35))),
                  ]),
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
                      onTap: () => _showProduct(context, product, apiBase, onAddToCart: () => _addToCart(product)),
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
                                  Text(readableApiValue(product['name'], fallback: 'Produk'), maxLines: 2, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w800, height: 1.2)),
                                  const SizedBox(height: 7),
                                  Text(formatRupiah(price), maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Color(0xFFD20A2E), fontWeight: FontWeight.w900, fontSize: 15)),
                                  const SizedBox(height: 5),
                                  Text(readableApiValue(product['store_name'], fallback: 'Toko UMKM'), maxLines: 1, overflow: TextOverflow.ellipsis,
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


class CustomerHeroSlider extends StatefulWidget {
  const CustomerHeroSlider({super.key, required this.slides, required this.apiBase});
  final List<dynamic> slides;
  final String apiBase;

  @override
  State<CustomerHeroSlider> createState() => _CustomerHeroSliderState();
}

class _CustomerHeroSliderState extends State<CustomerHeroSlider> {
  late final PageController _controller;
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    if (widget.slides.length > 1) {
      _timer = Timer.periodic(const Duration(milliseconds: 6500), (_) {
        if (!mounted || !_controller.hasClients) return;
        final next = (_page + 1) % widget.slides.length;
        _controller.animateToPage(next, duration: const Duration(milliseconds: 420), curve: Curves.easeInOut);
      });
    }
  }

  Future<void> _openTarget(String raw) async {
    final value = raw.trim();
    if (value.isEmpty) return;
    Uri? uri = Uri.tryParse(value);
    if (uri == null) return;
    if (!uri.hasScheme) {
      final base = Uri.tryParse(widget.apiBase);
      if (base == null) return;
      final origin = Uri(scheme: base.scheme, host: base.host, port: base.hasPort ? base.port : null);
      uri = origin.resolve(value);
    }
    if (uri.scheme != 'https' && uri.scheme != 'http') return;
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tautan banner tidak dapat dibuka.')));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tautan banner gagal dibuka.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final first = Map<String, dynamic>.from(widget.slides.first as Map);
    final ratioValue = double.tryParse((first['media_ratio'] ?? '').toString());
    final ratio = (ratioValue ?? 1.75).clamp(1.15, 2.2).toDouble();
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: AspectRatio(
            aspectRatio: ratio,
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.slides.length,
              onPageChanged: (value) => setState(() => _page = value),
              itemBuilder: (context, index) {
                final slide = Map<String, dynamic>.from(widget.slides[index] as Map);
                final path = (slide['image_path'] ?? slide['image'] ?? '').toString();
                final target = (slide['target_url'] ?? slide['url'] ?? '').toString();
                return Material(
                  color: const Color(0xFFF6F3F3),
                  child: InkWell(
                    onTap: target.trim().isEmpty ? null : () => _openTarget(target),
                    child: Image.network(
                      resolveMediaUrl(path, widget.apiBase),
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.broken_image_outlined, color: Color(0xFFB7AEB0), size: 32),
                          SizedBox(height: 6),
                          Text('Banner tidak dapat dimuat', style: TextStyle(color: Colors.black54)),
                        ]),
                      ),
                      loadingBuilder: (context, child, progress) => progress == null
                          ? child
                          : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (widget.slides.length > 1) ...[
          const SizedBox(height: 9),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(widget.slides.length, (index) => AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: _page == index ? 19 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: _page == index ? const Color(0xFFD20A2E) : const Color(0xFFDCCFD1),
                borderRadius: BorderRadius.circular(20),
              ),
            )),
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }
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

void _showProduct(BuildContext context, Map<String, dynamic> product, String apiBase, {required Future<bool> Function() onAddToCart}) {
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
            Text(readableApiValue(product['name'], fallback: 'Produk'), style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(formatRupiah(price), style: const TextStyle(fontSize: 22, color: Color(0xFFD20A2E), fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(readableApiValue(product['store_name'], fallback: 'UMKM Lokal'), style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 14),
            Text(readableApiValue(product['description'], fallback: 'Informasi produk belum tersedia.'), style: const TextStyle(height: 1.45)),
            const SizedBox(height: 12),
            Text('Stok tersedia: ${product['stock'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 18),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  final added = await onAddToCart();
                  if (added && context.mounted) Navigator.of(context).pop();
                },
                icon: const Icon(Icons.add_shopping_cart_rounded),
                label: const Text('Tambah ke Keranjang'),
              ),
            ),
            const SizedBox(height: 10),
            const Text('Harga dan stok mengikuti data server BersolekMart.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
      ),
    ),
  );
}

class CustomerCart extends ConsumerStatefulWidget {
  const CustomerCart({super.key});

  @override
  ConsumerState<CustomerCart> createState() => _CustomerCartState();
}

class _CustomerCartState extends ConsumerState<CustomerCart> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final api = ref.read(apiClientProvider);
    final result = await Future.wait([api.get('/cart'), api.baseUrl()]);
    final payload = result[0] as Map;
    final data = payload['data'] is Map ? Map<String, dynamic>.from(payload['data'] as Map) : <String, dynamic>{};
    return {'items': List<dynamic>.from(data['items'] as List? ?? const []), 'subtotal': data['subtotal'] ?? 0, 'count': data['count'] ?? 0, 'apiBase': result[1]};
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _updateQty(Map<String, dynamic> item, int qty) async {
    final id = item['id'] ?? item['line_key'];
    if (id == null) return;
    try {
      await ref.read(apiClientProvider).post('/cart/update', {'item_id': id, 'qty': qty});
      await _refresh();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Jumlah produk gagal diperbarui.')));
    }
  }

  Future<void> _remove(Map<String, dynamic> item) async {
    final id = item['id'] ?? item['line_key'];
    if (id == null) return;
    try {
      await ref.read(apiClientProvider).post('/cart/remove', {'item_id': id});
      await _refresh();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Produk gagal dihapus dari keranjang.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Keranjang')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) {
          return _ErrorPanel(
            message: 'Keranjang belum dapat dimuat. Pastikan API cart sudah dipasang di server.',
            onRetry: () => setState(() => _future = _load()),
          );
        }
        final data = snapshot.data ?? const <String, dynamic>{};
        final items = List<dynamic>.from(data['items'] as List? ?? const []);
        final apiBase = data['apiBase']?.toString() ?? '';
        if (items.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.shopping_basket_outlined, size: 56, color: Color(0xFFD20A2E)),
                SizedBox(height: 12),
                Text('Keranjang masih kosong', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                SizedBox(height: 6),
                Text('Pilih produk lokal lalu tekan Tambah ke Keranjang.', textAlign: TextAlign.center),
              ]),
            ),
          );
        }
        return Column(children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = Map<String, dynamic>.from(items[index] as Map);
                  final qty = int.tryParse(item['qty']?.toString() ?? '') ?? 1;
                  final price = _number(item['unit_price'] ?? item['variant_price'] ?? item['sale_price'] ?? item['price']);
                  final name = readableApiValue(item['name'], fallback: 'Produk');
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(width: 84, height: 84, child: ProductImageView(path: (item['image'] ?? '').toString(), apiBase: apiBase)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 4),
                          Text(readableApiValue(item['store_name'], fallback: 'UMKM Lokal'), style: const TextStyle(color: Colors.black54, fontSize: 12)),
                          const SizedBox(height: 7),
                          Text(formatRupiah(price), style: const TextStyle(color: Color(0xFFD20A2E), fontWeight: FontWeight.w900)),
                          const SizedBox(height: 8),
                          Row(children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: qty > 1 ? () => _updateQty(item, qty - 1) : null,
                              icon: const Icon(Icons.remove_circle_outline_rounded),
                            ),
                            Text('$qty', style: const TextStyle(fontWeight: FontWeight.w900)),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _updateQty(item, qty + 1),
                              icon: const Icon(Icons.add_circle_outline_rounded),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Hapus produk',
                              onPressed: () => _remove(item),
                              icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFD20A2E)),
                            ),
                          ]),
                        ])),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Color(0x11000000), blurRadius: 12, offset: Offset(0, -3))]),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  const Text('Subtotal', style: TextStyle(color: Colors.black54)),
                  Text(formatRupiah(data['subtotal']), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                ])),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: () async {
                    final result = await Navigator.of(context).push<Map<String, dynamic>>(
                      MaterialPageRoute<Map<String, dynamic>>(builder: (_) => const CustomerCheckoutPage()),
                    );
                    if (result == null || !mounted) return;
                    await _refresh();
                    final order = result['order'];
                    final payment = result['payment'];
                    if (order is Map && mounted) {
                      await Navigator.of(context).push<void>(MaterialPageRoute<void>(
                        builder: (_) => CustomerPaymentPage(
                          order: Map<String, dynamic>.from(order),
                          payment: payment is Map ? Map<String, dynamic>.from(payment) : const <String, dynamic>{},
                        ),
                      ));
                    }
                  },
                  child: const Text('Lanjut Checkout'),
                ),
              ]),
            ),
          ),
        ]);
      },
    ),
  );
}


class CustomerCheckoutPage extends ConsumerStatefulWidget {
  const CustomerCheckoutPage({super.key});

  @override
  ConsumerState<CustomerCheckoutPage> createState() => _CustomerCheckoutPageState();
}

class _CustomerCheckoutPageState extends ConsumerState<CustomerCheckoutPage> {
  bool _loading = true;
  bool _submitting = false;
  bool _locating = false;
  String? _error;
  String? _locationError;
  Map<String, dynamic>? _data;
  Position? _location;
  int? _addressId;
  int? _rateId;
  String? _shippingMethod;
  String? _paymentMethod;
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _truthy(dynamic value) => value == true || value?.toString() == '1' || value?.toString().toLowerCase() == 'true';

  List<dynamic> _list(dynamic payload) {
    if (payload is Map && payload['data'] is List) return List<dynamic>.from(payload['data'] as List);
    return const [];
  }

  Future<Position> _currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Aktifkan layanan lokasi perangkat terlebih dahulu.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw Exception('Izin lokasi presisi diperlukan untuk checkout sesuai kebijakan server.');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 18)),
    );
  }

  Future<List<dynamic>> _requestRates(Map<String, dynamic>? address, Position? location) async {
    final query = <String, String>{
      'city': (address?['city'] ?? 'Kota Probolinggo').toString(),
    };
    if (location != null) {
      query['lat'] = location.latitude.toString();
      query['lng'] = location.longitude.toString();
    }
    final payload = await ref.read(apiClientProvider).get('/checkout/rates', query: query);
    return _list(payload);
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      final optionsPayload = await api.get('/checkout/options');
      final options = optionsPayload is Map && optionsPayload['data'] is Map
          ? Map<String, dynamic>.from(optionsPayload['data'] as Map)
          : <String, dynamic>{};
      final addressPayload = await api.get('/addresses');
      final addresses = _list(addressPayload).whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
      if (_addressId == null || !addresses.any((a) => a['id'].toString() == _addressId.toString())) {
        final selected = addresses.where((a) => _truthy(a['is_default'])).firstOrNull ?? (addresses.isNotEmpty ? addresses.first : null);
        _addressId = selected == null ? null : int.tryParse(selected['id']?.toString() ?? '');
      }
      final selectedAddress = addresses.where((a) => a['id'].toString() == _addressId.toString()).firstOrNull;
      _location = null;
      _locationError = null;
      if (_truthy(options['requires_device_location'])) {
        try {
          _location = await _currentPosition();
          final maxAccuracy = double.tryParse((options['location_max_accuracy_m'] ?? 500).toString()) ?? 500;
          if (_location!.accuracy > maxAccuracy) {
            _locationError = 'Akurasi GPS ${_location!.accuracy.toStringAsFixed(0)} m; server mensyaratkan maksimal ${maxAccuracy.toStringAsFixed(0)} m. Ambil lokasi ulang di area terbuka.';
          }
        } catch (e) {
          _locationError = e.toString().replaceFirst('Exception: ', '');
        }
      }
      final rates = await _requestRates(selectedAddress, _location);
      final methods = List<dynamic>.from(options['payment_methods'] as List? ?? const []).map((e) => e.toString()).toList();
      if (_paymentMethod == null || !methods.contains(_paymentMethod)) _paymentMethod = methods.isNotEmpty ? methods.first : null;
      if (_rateId == null || !rates.any((r) => r is Map && r['id'].toString() == _rateId.toString())) {
        final chosenRate = rates.whereType<Map>().firstOrNull;
        _rateId = chosenRate == null ? null : int.tryParse(chosenRate['id']?.toString() ?? '');
        _shippingMethod = chosenRate?['method']?.toString();
      }
      if (mounted) setState(() {
        _data = {'options': options, 'addresses': addresses, 'rates': rates};
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  Future<void> _refreshRates() async {
    final data = _data;
    if (data == null) return;
    final addresses = List<dynamic>.from(data['addresses'] as List? ?? const []);
    final address = addresses.whereType<Map>().cast<Map<String, dynamic>>()
        .where((a) => a['id'].toString() == _addressId.toString()).firstOrNull;
    try {
      final rates = await _requestRates(address, _location);
      if (!mounted) return;
      final chosenRate = rates.whereType<Map>().firstOrNull;
      setState(() {
        _rateId = chosenRate == null ? null : int.tryParse(chosenRate['id']?.toString() ?? '');
        _shippingMethod = chosenRate?['method']?.toString();
        _data = {...data, 'rates': rates};
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tarif pengiriman gagal dimuat: ${e.toString().replaceFirst('Exception: ', '')}')));
    }
  }

  Future<void> _captureLocation() async {
    setState(() => _locating = true);
    try {
      final position = await _currentPosition();
      final options = Map<String, dynamic>.from(_data?['options'] as Map? ?? const {});
      final maxAccuracy = double.tryParse((options['location_max_accuracy_m'] ?? 500).toString()) ?? 500;
      setState(() {
        _location = position;
        _locationError = position.accuracy > maxAccuracy
            ? 'Akurasi GPS ${position.accuracy.toStringAsFixed(0)} m belum memenuhi batas ${maxAccuracy.toStringAsFixed(0)} m.'
            : null;
      });
      await _refreshRates();
    } catch (e) {
      setState(() => _locationError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  String _paymentLabel(String method) {
    switch (method) {
      case 'qris': return 'QRIS Bank Jatim (Mock)';
      case 'va': return 'Virtual Account Bank Jatim (Mock)';
      case 'transfer': return 'Transfer bank (verifikasi operator)';
      case 'gateway': return 'Payment gateway';
      case 'saldo': return 'Saldo member';
      case 'cod': return 'Bayar di tempat (COD)';
      default: return method.toUpperCase();
    }
  }

  String _rateLabel(Map rate) {
    final name = (rate['service'] ?? rate['label'] ?? rate['method'] ?? 'Pengiriman').toString();
    final eta = (rate['etd'] ?? '').toString();
    final price = formatRupiah(rate['cost']);
    return '$name${eta.isNotEmpty ? ' · $eta' : ''} — $price';
  }

  Future<void> _submit() async {
    final data = _data;
    if (data == null) return;
    final options = Map<String, dynamic>.from(data['options'] as Map? ?? const {});
    final addresses = List<dynamic>.from(data['addresses'] as List? ?? const []);
    final rates = List<dynamic>.from(data['rates'] as List? ?? const []);
    final address = addresses.whereType<Map>().where((a) => a['id'].toString() == _addressId.toString()).firstOrNull;
    final rate = rates.whereType<Map>().where((r) => r['id'].toString() == _rateId.toString()).firstOrNull;
    final methods = List<dynamic>.from(options['payment_methods'] as List? ?? const []).map((e) => e.toString()).toList();
    if (address == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pilih atau tambahkan alamat pengiriman terlebih dahulu.')));
      return;
    }
    if (rate == null || _shippingMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Belum ada tarif pengiriman aktif dari server. Checkout tidak dapat dilanjutkan.')));
      return;
    }
    if (_paymentMethod == null || !methods.contains(_paymentMethod)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Belum ada metode pembayaran yang diizinkan backend.')));
      return;
    }
    if (_truthy(options['can_checkout']) == false && options.containsKey('can_checkout')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Akun ini belum memenuhi syarat checkout pada mode UMKM.')));
      return;
    }
    if (_truthy(options['requires_device_location'])) {
      if (_location == null || (_locationError?.isNotEmpty ?? false)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_locationError ?? 'Lokasi perangkat wajib tersedia.')));
        return;
      }
      final maxAccuracy = double.tryParse((options['location_max_accuracy_m'] ?? 500).toString()) ?? 500;
      if (_location!.accuracy > maxAccuracy) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Akurasi GPS belum memenuhi syarat server. Ambil lokasi ulang.')));
        return;
      }
    }
    setState(() => _submitting = true);
    try {
      final body = <String, dynamic>{
        'address_id': _addressId,
        'shipping_method': _shippingMethod,
        'shipping_rate_id': _rateId,
        'payment_method': _paymentMethod,
        'guest_latitude': _location?.latitude,
        'guest_longitude': _location?.longitude,
        'guest_accuracy': _location?.accuracy,
        'note': _note.text.trim(),
      };
      final response = await ref.read(apiClientProvider).post('/checkout', body);
      final result = response is Map && response['data'] is Map
          ? Map<String, dynamic>.from(response['data'] as Map)
          : <String, dynamic>{};
      final order = result['order'];
      final payment = result['payment'];
      if (order is! Map) throw Exception('Server tidak mengembalikan detail order. Periksa log backend sebelum mencoba kembali.');
      if (!mounted) return;
      Navigator.of(context).pop(<String, dynamic>{
        'order': Map<String, dynamic>.from(order),
        'payment': payment is Map ? Map<String, dynamic>.from(payment) : <String, dynamic>{},
      });
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Checkout gagal: ${e.toString().replaceFirst('Exception: ', '')}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(appBar: AppBar(title: Text('Checkout')), body: Center(child: CircularProgressIndicator()));
    if (_error != null || _data == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined, size: 42, color: Color(0xFFD20A2E)),
            const SizedBox(height: 12),
            Text(_error ?? 'Checkout belum dapat dimuat.', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Coba lagi')),
          ]),
        )),
      );
    }
    final options = Map<String, dynamic>.from(_data!['options'] as Map? ?? const {});
    final addresses = List<dynamic>.from(_data!['addresses'] as List? ?? const []);
    final rates = List<dynamic>.from(_data!['rates'] as List? ?? const []);
    final methods = List<dynamic>.from(options['payment_methods'] as List? ?? const []).map((e) => e.toString()).toList();
    final selectedAddress = addresses.whereType<Map>().where((a) => a['id'].toString() == _addressId.toString()).firstOrNull;
    final canCheckout = !options.containsKey('can_checkout') || _truthy(options['can_checkout']);
    final requiresLocation = _truthy(options['requires_device_location']);
    final locationGood = !requiresLocation || (_location != null && (_locationError?.isEmpty ?? true));
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          const Text('Alamat pengiriman', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (addresses.isEmpty)
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
              const Text('Belum ada alamat tersimpan. Tambahkan alamat yang valid di Kota Probolinggo sebelum checkout.', textAlign: TextAlign.center),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => const CustomerAddressesPage()));
                  await _load();
                },
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Kelola alamat'),
              ),
            ])))
          else
            Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: DropdownButtonFormField<int>(
              value: _addressId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Pilih alamat utama'),
              items: addresses.whereType<Map>().map((raw) => Map<String, dynamic>.from(raw)).map((a) {
                final id = int.tryParse(a['id']?.toString() ?? '') ?? 0;
                final label = '${a['label'] ?? 'Alamat'} — ${a['recipient_name'] ?? ''}';
                final area = [a['district'], a['village']].where((v) => v != null && v.toString().isNotEmpty).join(', ');
                return DropdownMenuItem<int>(value: id, child: Text('$label${area.isNotEmpty ? ' · $area' : ''}', maxLines: 2, overflow: TextOverflow.ellipsis));
              }).toList(),
              onChanged: (value) async {
                setState(() => _addressId = value);
                await _refreshRates();
              },
            ))),
          const SizedBox(height: 18),
          const Text('Lokasi perangkat', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
            Icon(locationGood ? Icons.my_location_rounded : Icons.location_off_rounded, color: locationGood ? const Color(0xFF147D58) : const Color(0xFFD20A2E)),
            const SizedBox(width: 10),
            Expanded(child: Text(
              !requiresLocation
                  ? 'Server tidak mewajibkan GPS untuk checkout ini.'
                  : locationGood
                      ? 'Lokasi diperoleh · akurasi ${_location!.accuracy.toStringAsFixed(0)} m'
                      : (_locationError ?? 'Lokasi presisi diperlukan oleh backend.'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            )),
            if (requiresLocation) IconButton(
              tooltip: 'Ambil lokasi ulang',
              onPressed: _locating ? null : _captureLocation,
              icon: _locating ? const SizedBox(width: 18,height: 18,child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
            ),
          ]))),
          const SizedBox(height: 18),
          const Text('Metode pengiriman', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (rates.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('Tidak ada tarif pengiriman aktif. Pilihan ini berasal dari backend; hubungi operator untuk memeriksa konfigurasi pengiriman.')))
          else
            ...rates.whereType<Map>().map((raw) {
              final rate = Map<String, dynamic>.from(raw);
              final id = int.tryParse(rate['id']?.toString() ?? '') ?? 0;
              return Card(
                child: RadioListTile<int>(
                  value: id,
                  groupValue: _rateId,
                  onChanged: (value) => setState(() {
                    _rateId = value;
                    _shippingMethod = rate['method']?.toString();
                  }),
                  title: Text(_rateLabel(rate), style: const TextStyle(fontWeight: FontWeight.w700)),
                  dense: true,
                ),
              );
            }),
          const SizedBox(height: 18),
          const Text('Metode pembayaran', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (methods.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('Backend tidak menyediakan metode pembayaran yang aktif. Tidak ada pembayaran yang dibuat.')))
          else
            ...methods.map((method) => Card(child: RadioListTile<String>(
              value: method,
              groupValue: _paymentMethod,
              onChanged: (value) => setState(() => _paymentMethod = value),
              title: Text(_paymentLabel(method), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: method == 'qris' || method == 'va'
                  ? const Text('Simulasi Bank Jatim mengikuti status transaksi dari server.')
                  : null,
            ))),
          const SizedBox(height: 18),
          const Text('Catatan pesanan (opsional)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          TextField(controller: _note, maxLines: 3, decoration: const InputDecoration(hintText: 'Petunjuk tambahan untuk pesanan')),
          const SizedBox(height: 8),
          if (!canCheckout)
            const Text('Akun belum memenuhi syarat checkout untuk mode UMKM.', style: TextStyle(color: Color(0xFFD20A2E), fontWeight: FontWeight.w700)),
        ],
      ),
      bottomNavigationBar: SafeArea(child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: _submitting || addresses.isEmpty || rates.isEmpty || methods.isEmpty || !locationGood || !canCheckout ? null : _submit,
          icon: _submitting ? const SizedBox(width: 18,height: 18,child: CircularProgressIndicator(strokeWidth: 2,color: Colors.white)) : const Icon(Icons.lock_outline_rounded),
          label: Text(_submitting ? 'Memproses pesanan…' : 'Buat Pesanan'),
        ),
      )),
    );
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }
}

class CustomerPaymentPage extends ConsumerStatefulWidget {
  const CustomerPaymentPage({super.key, required this.order, required this.payment});
  final Map<String, dynamic> order;
  final Map<String, dynamic> payment;

  @override
  ConsumerState<CustomerPaymentPage> createState() => _CustomerPaymentPageState();
}

class _CustomerPaymentPageState extends ConsumerState<CustomerPaymentPage> {
  late Map<String, dynamic> _order;
  late Map<String, dynamic> _payment;
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _order = Map<String, dynamic>.from(widget.order);
    _payment = Map<String, dynamic>.from(widget.payment);
  }

  String _status() => (_payment['status'] ?? _order['flow_state'] ?? _order['status'] ?? 'unknown').toString();
  bool get _paid => const {'paid', 'success', 'completed', 'captured'}.contains(_status().toLowerCase());

  Future<void> _checkStatus() async {
    final id = int.tryParse(_order['id']?.toString() ?? '');
    if (id == null) return;
    setState(() { _checking = true; _error = null; });
    try {
      final response = await ref.read(apiClientProvider).get('/orders/$id');
      final data = response is Map && response['data'] is Map ? Map<String, dynamic>.from(response['data'] as Map) : <String, dynamic>{};
      final payment = data['payment'] is Map ? Map<String, dynamic>.from(data['payment'] as Map) : <String, dynamic>{};
      if (mounted) setState(() { _order = data.isEmpty ? _order : data; _payment = payment.isEmpty ? _payment : payment; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _openMockPayment() async {
    final code = (_order['code'] ?? '').toString();
    if (code.isEmpty) return;
    final uri = Uri.https('bersolekmart.com', '/payment/mock/$code');
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (!launched && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Halaman simulasi pembayaran tidak dapat dibuka.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Halaman simulasi pembayaran gagal dibuka.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final payload = _payment['provider_payload'] is Map
        ? Map<String, dynamic>.from(_payment['provider_payload'] as Map)
        : <String, dynamic>{};
    final method = (_payment['method'] ?? _order['payment_method'] ?? '').toString();
    final status = _status();
    final amount = _payment['amount'] ?? _order['total'];
    final qrImage = (payload['qr_image_url'] ?? '').toString();
    final vaNumber = (payload['va_number'] ?? '').toString();
    final provider = (_payment['provider'] ?? payload['provider'] ?? '').toString().toLowerCase();
    return Scaffold(
      appBar: AppBar(title: const Text('Pembayaran Pesanan')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _paid ? const Color(0xFFE5F7ED) : const Color(0xFFFFF0F2),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(children: [
              Icon(_paid ? Icons.check_circle_rounded : Icons.hourglass_top_rounded, size: 42, color: _paid ? const Color(0xFF147D58) : const Color(0xFFD20A2E)),
              const SizedBox(height: 8),
              Text(_paid ? 'Pembayaran terverifikasi server' : 'Status pembayaran: $status',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text('Order ${_order['code'] ?? '-'}', style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 8),
              Text(formatRupiah(amount), style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
            ]),
          ),
          const SizedBox(height: 18),
          Card(child: ListTile(
            leading: const Icon(Icons.payment_rounded, color: Color(0xFFD20A2E)),
            title: const Text('Metode pembayaran'),
            subtitle: Text(method.toUpperCase()),
          )),
          if (!_paid && provider.contains('mock_bank_jatim') && method == 'qris') ...[
            const SizedBox(height: 14),
            const Text('QRIS Bank Jatim (Mock)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            if (qrImage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(child: Image.network(
                  qrImage, width: 240, height: 240, fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(Icons.qr_code_2_rounded, size: 180, color: Color(0xFF171113)),
                )),
              ),
            if ((payload['qr_payload'] ?? '').toString().isNotEmpty)
              SelectableText((payload['qr_payload']).toString(), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text('Ini adalah simulasi Bank Jatim. Status pembayaran hanya berubah setelah server menerima callback/transaksi mock yang sah.',
              style: TextStyle(color: Colors.black54, height: 1.4)),
          ],
          if (!_paid && provider.contains('mock_bank_jatim') && method == 'va') ...[
            const SizedBox(height: 14),
            const Text('Virtual Account Bank Jatim (Mock)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            SelectableText(vaNumber.isEmpty ? 'Nomor VA belum diberikan backend.' : vaNumber,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 1.2), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            const Text('Gunakan hanya untuk pengujian sandbox. Nomor VA dan status ditampilkan dari respons backend.',
              style: TextStyle(color: Colors.black54, height: 1.4)),
          ],
          if (!_paid && provider.contains('mock_bank_jatim')) ...[
            const SizedBox(height: 14),
            FilledButton.icon(onPressed: _openMockPayment, icon: const Icon(Icons.open_in_browser_rounded), label: const Text('Buka simulasi Bank Jatim')),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Color(0xFFD20A2E))),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _checking ? null : _checkStatus,
            icon: _checking ? const SizedBox(width: 18,height: 18,child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded),
            label: Text(_checking ? 'Memeriksa…' : 'Periksa status pembayaran'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Kembali ke aplikasi'),
          ),
        ],
      ),
    );
  }
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
      if (items.isEmpty) {
        return ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
          SizedBox(height: 100), Icon(Icons.receipt_long_outlined, size: 54, color: Color(0xFFB7AEB0)),
          SizedBox(height: 12), Center(child: Text('Belum ada pesanan.')),
        ]);
      }
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final order = Map<String, dynamic>.from(items[index] as Map);
          return Card(child: ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xFFFFE4E8), child: Icon(Icons.receipt_long, color: Color(0xFFD20A2E))),
            title: Text('${order['code'] ?? order['order_code'] ?? 'Pesanan'}', style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(readableApiValue(order['flow_state'] ?? order['status'])),
            trailing: Text(formatRupiah(order['total']), style: const TextStyle(color: Color(0xFFD20A2E), fontWeight: FontWeight.w900)),
          ));
        },
      );
    },
  );
}

class CustomerProfile extends ConsumerWidget {
  const CustomerProfile({super.key});

  void _open(BuildContext context, String title, IconData icon, Map<String, dynamic> user, List<String> keys, String emptyText) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _CustomerAccountDetailPage(
        title: title,
        icon: icon,
        user: user,
        keys: keys,
        emptyText: emptyText,
      ),
    ));
  }

  void _openAddresses(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CustomerAddressesPage()));
  }

  void _openBanks(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CustomerBankAccountsPage()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final user = session?.user ?? const <String, dynamic>{};
    final name = readableApiValue(user['full_name'], fallback: 'Pengguna BersolekMart');
    final contact = readableApiValue(user['email'] ?? user['phone']);

    Widget item(IconData icon, String title, String subtitle, VoidCallback onTap) => Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: const Color(0xFFFFE5E9), borderRadius: BorderRadius.circular(13)),
          child: Icon(icon, color: const Color(0xFFD20A2E)),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFD20A2E), Color(0xFF7D0018)]),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(color: Colors.white.withAlpha(28), borderRadius: BorderRadius.circular(20)),
              child: const Icon(Icons.person_rounded, color: Colors.white, size: 36),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(contact, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              const Text('Akun Pembeli', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ])),
          ]),
        ),
        const SizedBox(height: 22),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('Akun Saya', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        ),
        item(Icons.person_outline_rounded, 'Profil Saya', 'Informasi akun dan kontak',
          () async {
            final saved = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
              builder: (_) => AccountProfileEditPage(title: 'Profil Saya', initialUser: user),
            ));
            if (saved == true && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profil berhasil diperbarui.')));
            }
          }),
        const SizedBox(height: 8),
        item(Icons.location_on_outlined, 'Alamat Pengiriman', 'Lihat alamat yang tersedia pada akun',
          () => _openAddresses(context)),
        const SizedBox(height: 8),
        item(Icons.account_balance_outlined, 'Rekening', 'Informasi rekening yang tersedia pada akun',
          () => _openBanks(context)),
        const SizedBox(height: 8),
        item(Icons.support_agent_outlined, 'Bantuan', 'Informasi bantuan BersolekMart',
          () => _open(context, 'Bantuan', Icons.support_agent_outlined, user, const [],
            'Untuk bantuan transaksi, gunakan kanal bantuan yang tersedia pada PWA BersolekMart.')),
        const SizedBox(height: 22),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFD20A2E),
            side: const BorderSide(color: Color(0xFFD20A2E)),
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Keluar dari akun'),
        ),
      ],
    );
  }
}

class CustomerAddressesPage extends ConsumerStatefulWidget {
  const CustomerAddressesPage({super.key});

  @override
  ConsumerState<CustomerAddressesPage> createState() => _CustomerAddressesPageState();
}

class _CustomerAddressesPageState extends ConsumerState<CustomerAddressesPage> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<dynamic>> _load() async {
    final payload = await ref.read(apiClientProvider).get('/addresses');
    return List<dynamic>.from(payload is Map ? payload['data'] as List? ?? const [] : const []);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Alamat Pengiriman')),
    body: FutureBuilder<List<dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) {
          return _ErrorPanel(
            message: 'Alamat belum dapat dimuat. Pastikan endpoint API /addresses sudah tersedia di server.',
            onRetry: () => setState(() => _future = _load()),
          );
        }
        final addresses = snapshot.data ?? const [];
        if (addresses.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.location_off_outlined, size: 52, color: Color(0xFFD20A2E)),
                SizedBox(height: 12),
                Text('Belum ada alamat tersimpan.', style: TextStyle(fontWeight: FontWeight.w800)),
                SizedBox(height: 6),
                Text('Pengelolaan alamat perlu endpoint simpan yang sesuai dengan PWA.', textAlign: TextAlign.center),
              ]),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: addresses.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final address = Map<String, dynamic>.from(addresses[index] as Map);
            final label = readableApiValue(address['label'], fallback: 'Alamat');
            final name = readableApiValue(address['recipient_name'], fallback: 'Penerima');
            final phone = readableApiValue(address['phone'], fallback: '');
            final line = readableApiValue(address['address_line'], fallback: '');
            final area = [
              address['village'], address['district'], address['city'], address['province']
            ].where((v) => v != null && v.toString().trim().isNotEmpty).join(', ');
            final isDefault = address['is_default']?.toString() == '1' || address['is_default'] == true;
            return Card(child: ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFFFFE5E9), child: Icon(Icons.location_on_outlined, color: Color(0xFFD20A2E))),
              title: Row(children: [
                Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900))),
                if (isDefault) const Chip(label: Text('Utama'), visualDensity: VisualDensity.compact),
              ]),
              subtitle: Text([name, phone, line, area].where((v) => v.isNotEmpty).join('\n')),
              isThreeLine: true,
            ));
          },
        );
      },
    ),
  );
}

class CustomerBankAccountsPage extends ConsumerStatefulWidget {
  const CustomerBankAccountsPage({super.key});

  @override
  ConsumerState<CustomerBankAccountsPage> createState() => _CustomerBankAccountsPageState();
}

class _CustomerBankAccountsPageState extends ConsumerState<CustomerBankAccountsPage> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<dynamic>> _load() async {
    final payload = await ref.read(apiClientProvider).get('/banks');
    return List<dynamic>.from(payload is Map ? payload['data'] as List? ?? const [] : const []);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Rekening')),
    body: FutureBuilder<List<dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) {
          return _ErrorPanel(
            message: 'Rekening belum dapat dimuat. Endpoint API /banks belum terverifikasi pada server.',
            onRetry: () => setState(() => _future = _load()),
          );
        }
        final accounts = snapshot.data ?? const [];
        if (accounts.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.account_balance_outlined, size: 52, color: Color(0xFFD20A2E)),
                SizedBox(height: 12),
                Text('Belum ada rekening tersimpan.', style: TextStyle(fontWeight: FontWeight.w800)),
                SizedBox(height: 6),
                Text('Pengelolaan rekening perlu endpoint API yang terhubung ke data PWA.', textAlign: TextAlign.center),
              ]),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: accounts.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final account = Map<String, dynamic>.from(accounts[index] as Map);
            final isDefault = account['is_default']?.toString() == '1' || account['is_default'] == true;
            final accountNumber = readableApiValue(account['account_number'], fallback: '');
            final digits = accountNumber.replaceAll(RegExp(r'[^0-9]'), '');
            final maskedNumber = digits.length > 4 ? '•••• ${digits.substring(digits.length - 4)}' : accountNumber;
            return Card(child: ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFFFFE5E9), child: Icon(Icons.account_balance_outlined, color: Color(0xFFD20A2E))),
              title: Text(readableApiValue(account['bank_name'], fallback: 'Bank'), style: const TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text('${readableApiValue(account['account_name'], fallback: 'Pemilik rekening')}\n$maskedNumber'),
              trailing: isDefault ? const Chip(label: Text('Utama')) : null,
            ));
          },
        );
      },
    ),
  );
}

class _CustomerAccountDetailPage extends StatelessWidget {
  const _CustomerAccountDetailPage({
    required this.title,
    required this.icon,
    required this.user,
    required this.keys,
    required this.emptyText,
  });

  final String title;
  final IconData icon;
  final Map<String, dynamic> user;
  final List<String> keys;
  final String emptyText;

  String _label(String key) {
    const labels = {
      'full_name': 'Nama lengkap', 'name': 'Nama', 'email': 'Email',
      'phone': 'Nomor telepon', 'nik': 'NIK', 'address': 'Alamat',
      'addresses': 'Daftar alamat', 'shipping_address': 'Alamat pengiriman',
      'default_address': 'Alamat utama', 'recipient_name': 'Nama penerima',
      'address_line': 'Detail alamat', 'kelurahan': 'Kelurahan',
      'kecamatan': 'Kecamatan', 'city': 'Kota', 'postal_code': 'Kode pos',
      'bank_account': 'Rekening', 'bank_accounts': 'Daftar rekening',
      'bank_name': 'Nama bank', 'bank_code': 'Kode bank',
      'account_name': 'Nama pemilik rekening', 'account_number': 'Nomor rekening',
    };
    return labels[key] ?? key.replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final fields = keys.where((key) => user[key] != null && readableApiValue(user[key], fallback: '').isNotEmpty).toList();
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: fields.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 52, color: const Color(0xFFD20A2E)),
                  const SizedBox(height: 14),
                  Text(emptyText, textAlign: TextAlign.center, style: const TextStyle(height: 1.5)),
                ]),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final key in fields)
                  Card(
                    child: ListTile(
                      title: Text(_label(key), style: const TextStyle(color: Colors.black54, fontSize: 12)),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(readableApiValue(user[key]), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                const Text(
                  'Halaman ini menampilkan data yang dikirim oleh API akun. Perubahan data hanya diaktifkan setelah kontrak endpoint update dari backend terverifikasi.',
                  style: TextStyle(color: Colors.black54, height: 1.45),
                ),
              ],
            ),
    );
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
