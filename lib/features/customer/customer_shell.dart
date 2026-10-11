import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../account/account_profile_edit_page.dart';
import '../account/member_data_pages.dart';
import 'checkout_page.dart';

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
  if (payload is! Map || payload['ok'] != true) {
    throw const FormatException('Respons katalog bukan envelope JSON API yang sukses.');
  }
  final data = payload['data'];
  if (data is! List) {
    throw const FormatException('Field data katalog harus berupa array.');
  }
  for (final product in data) {
    if (product is! Map ||
        product['id'] == null ||
        product['name'] == null ||
        product['name'].toString().trim().isEmpty ||
        !product.containsKey('price')) {
      throw const FormatException('Salah satu item katalog tidak memiliki field produk wajib.');
    }
  }
  return List<dynamic>.from(data);
}

List<dynamic> catalogCategoriesFromPayload(dynamic payload) {
  if (payload is! Map || payload['ok'] != true || payload['data'] is! List) {
    throw const FormatException('Respons kategori tidak sesuai kontrak API.');
  }
  final data = payload['data'] as List;
  if (data.any((category) => category is! Map)) {
    throw const FormatException('Item kategori tidak sesuai format API.');
  }
  return List<dynamic>.from(data);
}

String catalogErrorMessage(Object error) {
  if (error is ApiException) {
    final code = (error.code ?? '').toUpperCase();
    if (code == 'NETWORK_ERROR') return 'Server katalog tidak dapat dijangkau. Periksa koneksi internet lalu coba lagi.';
    if (code == 'REQUEST_TIMEOUT') return 'Server katalog merespons terlalu lama. Coba muat ulang.';
    if (code == 'API_DISABLED') return 'Layanan katalog sedang dinonaktifkan. Coba lagi nanti.';
    if (error.statusCode == 404) return 'Endpoint katalog tidak ditemukan pada server. Hubungi pengelola aplikasi.';
    if (error.statusCode == 401 || error.statusCode == 403) return 'Server menolak permintaan katalog. Periksa konfigurasi akses API.';
    if (error.statusCode >= 500) return 'Server katalog sedang mengalami kendala. Coba lagi nanti.';
  }
  if (error is FormatException) {
    return 'Respons katalog dari server tidak sesuai format yang diharapkan. Muat ulang atau hubungi pengelola.';
  }
  return 'Katalog belum dapat dimuat. Periksa koneksi lalu coba lagi.';
}

String resolveMediaUrl(String raw, String apiBase) {
  final value = raw.trim();
  if (value.isEmpty) return '';
  final parsed = Uri.tryParse(value);
  if (value.startsWith('//')) return 'https:$value';
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
      CustomerHome(key: ValueKey('home-${_selectedCategory ?? 'all'}'), initialCategory: _selectedCategory, onOpenCart: () => setState(() {
        _cartRevision++;
        _index = 2;
      })),
      CustomerCategories(onSelect: (category) => setState(() {
        _selectedCategory = category;
        _index = 0;
      })),
      CustomerCart(
        key: ValueKey('cart-$_cartRevision'),
        onContinueShopping: () => setState(() => _index = 0),
      ),
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
            Image.asset(
              'assets/branding/bersolek-mart-adaptive-foreground.png',
              width: 38,
              height: 38,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(Icons.shopping_bag_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 10),
            const Text('BersolekMart', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -.3)),
          ],
        ),
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() {
          if (value == 2) _cartRevision++;
          _index = value;
        }),
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
  // Keep optional CMS/category calls independent from the primary product request.
  late Future<List<dynamic>> _future;
  final _search = TextEditingController();
  Timer? _searchDebounce;
  String? _category;
  String _sortBy = 'recommended';
  List<dynamic> _categories = const [];
  List<dynamic> _heroSlides = const [];
  String _apiBase = ApiClient.defaultBaseUrl;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    _future = _loadProducts();
    _loadOptionalContent();
  }

  @override
  void didUpdateWidget(covariant CustomerHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCategory != widget.initialCategory) {
      _category = widget.initialCategory;
      _future = _loadProducts();
    }
  }

  Future<bool> _addToCart(Map<String, dynamic> product, {int quantity = 1}) async {
    final id = int.tryParse(product['id']?.toString() ?? '') ?? 0;
    if (id < 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Produk ini tidak memiliki ID yang valid.')));
      return false;
    }
    try {
      await ref.read(apiClientProvider).post('/cart/items', {'product_id': id, 'qty': quantity});
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

  Future<List<dynamic>> _loadProducts() async {
    final api = ref.read(apiClientProvider);
    final query = <String, String>{'limit': '24'};
    if (_search.text.trim().isNotEmpty) query['q'] = _search.text.trim();
    if (_category != null && _category!.isNotEmpty) query['category'] = _category!;

    try {
      final payload = await api.get('/catalog/products', query: query);
      final products = List<dynamic>.from(catalogProductsFromPayload(payload));
      double effectivePrice(dynamic raw) {
        final item = Map<String, dynamic>.from(raw as Map);
        final base = _number(item['price']);
        final sale = _number(item['sale_price']);
        return sale > 0 && base > 0 && sale < base ? sale : base;
      }

      switch (_sortBy) {
        case 'price_low':
          products.sort((a, b) => effectivePrice(a).compareTo(effectivePrice(b)));
          break;
        case 'price_high':
          products.sort((a, b) => effectivePrice(b).compareTo(effectivePrice(a)));
          break;
        case 'name':
          products.sort((a, b) => readableApiValue(a['name']).toLowerCase()
              .compareTo(readableApiValue(b['name']).toLowerCase()));
          break;
        // "recommended" preserves the backend's existing order.
      }
      if (kDebugMode) {
        debugPrint('[BersolekMart Catalog] products loaded=${products.length}; sort=$_sortBy; query=${query.keys.join(',')}.');
      }
      return products;
    } catch (error) {
      if (kDebugMode) {
        final detail = error is ApiException
            ? 'HTTP ${error.statusCode}, code=${error.code ?? '-'}'
            : error.runtimeType.toString();
        debugPrint('[BersolekMart Catalog] products request/payload failed ($detail).');
      }
      rethrow;
    }
  }

  void _loadOptionalContent() {
    final api = ref.read(apiClientProvider);
    unawaited(_loadApiBase(api));
    unawaited(_loadCategories(api));
    unawaited(_loadCmsHome(api));
  }

  Future<void> _loadApiBase(ApiClient api) async {
    try {
      final base = await api.baseUrl();
      if (mounted && base != _apiBase) setState(() => _apiBase = base);
    } catch (error) {
      if (kDebugMode) debugPrint('[BersolekMart Catalog] API base URL unavailable (${error.runtimeType}).');
    }
  }

  Future<void> _loadCategories(ApiClient api) async {
    try {
      final payload = await api.get('/catalog/categories');
      final categories = catalogCategoriesFromPayload(payload);
      if (mounted) setState(() => _categories = categories);
      if (kDebugMode) debugPrint('[BersolekMart Catalog] categories loaded=${categories.length}.');
    } catch (error) {
      if (kDebugMode) {
        final detail = error is ApiException
            ? 'HTTP ${error.statusCode}, code=${error.code ?? '-'}'
            : error.runtimeType.toString();
        debugPrint('[BersolekMart Catalog] categories unavailable ($detail).');
      }
      // Category failure is supplementary and must not hide the product list.
    }
  }

  Future<void> _loadCmsHome(ApiClient api) async {
    try {
      final payload = await api.get('/cms/home');
      final cms = payload is Map && payload['data'] is Map
          ? Map<String, dynamic>.from(payload['data'] as Map)
          : <String, dynamic>{};
      final slides = cms['hero_slides'] is List
          ? List<dynamic>.from(cms['hero_slides'] as List)
          : cms['hero'] is Map
              ? <dynamic>[cms['hero']]
              : <dynamic>[];
      if (mounted) setState(() => _heroSlides = slides);
      if (kDebugMode) debugPrint('[BersolekMart Catalog] CMS hero slides=${slides.length}.');
    } catch (error) {
      if (kDebugMode) {
        final detail = error is ApiException
            ? 'HTTP ${error.statusCode}, code=${error.code ?? '-'}'
            : error.runtimeType.toString();
        debugPrint('[BersolekMart Catalog] CMS unavailable ($detail).');
      }
      // CMS banners are optional and never block the product list.
    }
  }

  void _reload() {
    _searchDebounce?.cancel();
    setState(() => _future = _loadProducts());
  }

  void _scheduleSearch(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _reload();
    });
  }

  Future<void> _refresh() async {
    final next = _loadProducts();
    setState(() => _future = next);
    _loadOptionalContent();
    try {
      await next;
    } catch (_) {
      // FutureBuilder presents the error/retry state.
    }
  }

  Widget _catalogLoadingGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: .73,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (context, index) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: const Color(0xFFF1EAEC),
                alignment: Alignment.center,
                child: const Icon(Icons.image_outlined, size: 30, color: Color(0xFFD2C6C9)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 11),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(height: 10, width: double.infinity, decoration: BoxDecoration(color: const Color(0xFFEDE6E8), borderRadius: BorderRadius.circular(6))),
                const SizedBox(height: 7),
                Container(height: 10, width: 78, decoration: BoxDecoration(color: const Color(0xFFEDE6E8), borderRadius: BorderRadius.circular(6))),
                const SizedBox(height: 9),
                Container(height: 14, width: 92, decoration: BoxDecoration(color: const Color(0xFFFFE0E6), borderRadius: BorderRadius.circular(6))),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _catalogStatePanel({
    required IconData icon,
    required String title,
    required String message,
    required Widget action,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 18),
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFEDE3E5)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(color: const Color(0xFFFFE9ED), borderRadius: BorderRadius.circular(18)),
            child: Icon(icon, size: 30, color: const Color(0xFFD20A2E)),
          ),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF6B6265), height: 1.4, fontSize: 13)),
          const SizedBox(height: 14),
          action,
        ],
      ),
    );
  }

  Widget _buildHomeContent(AsyncSnapshot<List<dynamic>> snapshot) {
    final loading = snapshot.connectionState == ConnectionState.waiting;
    final error = snapshot.hasError ? snapshot.error : null;
    final items = (!loading && error == null) ? (snapshot.data ?? const <dynamic>[]) : const <dynamic>[];
    final apiBase = _apiBase;
    final categories = _categories;
    final hasFilter = _search.text.trim().isNotEmpty || (_category?.isNotEmpty ?? false);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
      children: [
        _CmsHeroCarousel(slides: _heroSlides, apiBase: apiBase),
        const SizedBox(height: 10),
        TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          onChanged: _scheduleSearch,
          onSubmitted: (_) => _reload(),
          decoration: InputDecoration(
            hintText: 'Cari produk, toko, atau kategori…',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(
              tooltip: 'Cari',
              icon: const Icon(Icons.arrow_forward_rounded),
              onPressed: _reload,
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 14),
        Row(children: [
          const Expanded(child: Text('Kategori', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
          TextButton(
            onPressed: _category == null ? null : () {
              _category = null;
              _reload();
            },
            child: const Text('Semua'),
          ),
        ]),
        SizedBox(
          height: 82,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _CategoryTile(
                  label: 'Semua',
                  icon: Icons.apps_rounded,
                  selected: _category == null,
                  onTap: () {
                    if (_category == null) return;
                    _category = null;
                    _reload();
                  },
                );
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
        const SizedBox(height: 12),
        Row(children: [
          const Expanded(child: Text('Produk UMKM Lokal', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900))),
          if (loading)
            const SizedBox.square(dimension: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD20A2E)))
          else
            Text(error != null ? '—' : '${items.length} produk', style: const TextStyle(color: Colors.black54, fontSize: 11)),
          const SizedBox(width: 2),
          PopupMenuButton<String>(
            tooltip: 'Urutkan produk',
            icon: const Icon(Icons.sort_rounded, size: 22),
            onSelected: (value) {
              if (value == _sortBy) return;
              setState(() => _sortBy = value);
              _reload();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'recommended', child: Text('Rekomendasi')),
              PopupMenuItem(value: 'price_low', child: Text('Harga terendah')),
              PopupMenuItem(value: 'price_high', child: Text('Harga tertinggi')),
              PopupMenuItem(value: 'name', child: Text('Nama A–Z')),
            ],
          ),
        ]),
        const SizedBox(height: 8),
        if (loading) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(2, 4, 2, 10),
            child: Text('Memuat katalog dari server…', style: TextStyle(color: Color(0xFF6B6265), fontSize: 12)),
          ),
          _catalogLoadingGrid(),
        ] else if (error != null)
          _catalogStatePanel(
            icon: Icons.cloud_off_rounded,
            title: 'Produk belum dapat dimuat',
            message: catalogErrorMessage(error),
            action: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Coba muat ulang'),
              ),
            ),
          )
        else if (items.isEmpty)
          _catalogStatePanel(
            icon: Icons.shopping_bag_outlined,
            title: hasFilter ? 'Produk tidak ditemukan' : 'Belum ada produk aktif',
            message: hasFilter
                ? 'Coba kata kunci lain atau hapus filter untuk melihat produk yang tersedia.'
                : 'Katalog berhasil dimuat, tetapi server belum mengembalikan produk aktif.',
            action: hasFilter
                ? OutlinedButton.icon(
                    onPressed: () {
                      _search.clear();
                      _category = null;
                      _reload();
                    },
                    icon: const Icon(Icons.filter_alt_off_rounded),
                    label: const Text('Hapus pencarian dan filter'),
                  )
                : OutlinedButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Muat ulang katalog'),
                  ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: .73,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemBuilder: (context, index) {
              final product = Map<String, dynamic>.from(items[index] as Map);
              final basePrice = _number(product['price']);
              final salePrice = _number(product['sale_price']);
              final price = salePrice > 0 && basePrice > 0 && salePrice < basePrice ? salePrice : basePrice;
              final image = (product['image'] ?? '').toString();
              return InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => _showProduct(
                  context,
                  product,
                  apiBase,
                  onAddToCart: (quantity) => _addToCart(product, quantity: quantity),
                ),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AspectRatio(
                        aspectRatio: 1.30,
                        child: Hero(
                          tag: 'product-${product['id']}',
                          child: ProductImageView(path: image, apiBase: apiBase),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(readableApiValue(product['name'], fallback: 'Produk'), maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w800, height: 1.2)),
                              const Spacer(),
                              Text(formatRupiah(price), maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Color(0xFFD20A2E), fontWeight: FontWeight.w900, fontSize: 15)),
                              const SizedBox(height: 3),
                              Text(readableApiValue(product['store_name'], fallback: 'Toko UMKM'), maxLines: 1,
                                overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.black54)),
                            ],
                          ),
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
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snapshot) => _buildHomeContent(snapshot),
      ),
    );
  }
  @override
  void dispose() {
    _searchDebounce?.cancel();
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
    final pathOnly = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    if (url.isEmpty || pathOnly.split('?').first.endsWith('.svg')) {
      if (kDebugMode && pathOnly.endsWith('.svg')) {
        debugPrint('[BersolekMart Image] SVG image is not natively supported by this widget; using fallback.');
      }
      return const _ImageFallback();
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      errorBuilder: (_, error, _) {
        if (kDebugMode) {
          final uri = Uri.tryParse(url);
          debugPrint('[BersolekMart Image] ${uri?.host ?? '-'}${uri?.path ?? '-'} failed (${error.runtimeType}).');
        }
        return const _ImageFallback();
      },
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
    color: const Color(0xFFF7EFF1),
    alignment: Alignment.center,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          const SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD20A2E)),
          )
        else
          const Icon(Icons.image_not_supported_outlined, size: 30, color: Color(0xFF89797D)),
        const SizedBox(height: 7),
        Text(
          loading ? 'Memuat foto…' : 'Foto tidak tersedia',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF89797D)),
        ),
      ],
    ),
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

void _showProduct(
  BuildContext context,
  Map<String, dynamic> product,
  String apiBase, {
  required Future<bool> Function(int quantity) onAddToCart,
}) {
  Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => _CustomerProductDetailPage(
        product: product,
        apiBase: apiBase,
        onAddToCart: onAddToCart,
      ),
    ),
  );
}

class _CustomerProductDetailPage extends StatefulWidget {
  const _CustomerProductDetailPage({
    required this.product,
    required this.apiBase,
    required this.onAddToCart,
  });

  final Map<String, dynamic> product;
  final String apiBase;
  final Future<bool> Function(int quantity) onAddToCart;

  @override
  State<_CustomerProductDetailPage> createState() => _CustomerProductDetailPageState();
}

class _CustomerProductDetailPageState extends State<_CustomerProductDetailPage> {
  int _quantity = 1;
  bool _adding = false;

  num get _basePrice => _number(widget.product['price']);
  num get _salePrice => _number(widget.product['sale_price']);
  num get _price => _salePrice > 0 && _basePrice > 0 && _salePrice < _basePrice
      ? _salePrice
      : _basePrice;
  int? get _stock {
    final raw = widget.product['stock'];
    if (raw == null || raw.toString().trim().isEmpty) return null;
    return int.tryParse(raw.toString());
  }
  bool get _outOfStock => _stock != null && _stock! <= 0;

  Future<void> _add() async {
    if (_adding || _outOfStock) return;
    setState(() => _adding = true);
    try {
      final added = await widget.onAddToCart(_quantity);
      if (added && mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = readableApiValue(widget.product['name'], fallback: 'Produk UMKM');
    final description = readableApiValue(
      widget.product['description'],
      fallback: 'Informasi tambahan produk belum tersedia.',
    );
    final storeName = readableApiValue(widget.product['store_name'], fallback: 'UMKM lokal');
    final image = (widget.product['image'] ?? '').toString();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F4F4),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF171113),
        elevation: 0,
        title: const Text('Detail Produk', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: AspectRatio(
                    aspectRatio: 1.08,
                    child: Hero(
                      tag: 'product-${widget.product['id']}',
                      child: ProductImageView(path: image, apiBase: widget.apiBase),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(17),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFEDE5E6)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFE8EB),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('PRODUK UMKM',
                              style: TextStyle(color: Color(0xFFD20A2E), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: .7)),
                          ),
                          const Spacer(),
                          if (_outOfStock)
                            const Text('Stok habis', style: TextStyle(color: Color(0xFFB00020), fontWeight: FontWeight.w800, fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(name, style: const TextStyle(fontSize: 24, height: 1.15, fontWeight: FontWeight.w900, letterSpacing: -.4)),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(child: Text(
                            formatRupiah(_price),
                            style: const TextStyle(color: Color(0xFFD20A2E), fontSize: 25, fontWeight: FontWeight.w900),
                          )),
                          if (_price < _basePrice)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(formatRupiah(_basePrice),
                                style: const TextStyle(color: Colors.black45, decoration: TextDecoration.lineThrough, fontSize: 13)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.storefront_outlined, size: 19, color: Color(0xFFD20A2E)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(storeName, style: const TextStyle(fontWeight: FontWeight.w800))),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 14),
                      const Text('Deskripsi produk', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 7),
                      Text(description, style: const TextStyle(color: Color(0xFF5F5659), height: 1.5)),
                      if (_stock != null) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Icon(Icons.inventory_2_outlined, size: 18, color: Colors.black54),
                            const SizedBox(width: 8),
                            Text('Stok tersedia: ${_stock!}',
                              style: TextStyle(fontWeight: FontWeight.w700, color: _outOfStock ? const Color(0xFFB00020) : Colors.black87)),
                          ],
                        ),
                      ],
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          const Expanded(child: Text('Jumlah', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7F3F4),
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(color: const Color(0xFFE8DDE0)),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _adding || _quantity <= 1 ? null : () => setState(() => _quantity--),
                                  icon: const Icon(Icons.remove_rounded),
                                ),
                                SizedBox(width: 28, child: Text('$_quantity', textAlign: TextAlign.center,
                                  style: const TextStyle(fontWeight: FontWeight.w900))),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _adding || _outOfStock || (_stock != null && _quantity >= _stock!)
                                      ? null
                                      : () => setState(() => _quantity++),
                                  icon: const Icon(Icons.add_rounded),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Center(child: Text('Harga dan stok mengikuti data server BersolekMart.',
                  style: TextStyle(fontSize: 11, color: Colors.black54))),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Color(0x10000000), blurRadius: 16, offset: Offset(0, -4))],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Total sementara', style: TextStyle(color: Colors.black54, fontSize: 11)),
                        const SizedBox(height: 2),
                        Text(formatRupiah(_price * _quantity),
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _adding || _outOfStock ? null : _add,
                      icon: _adding
                          ? const SizedBox.square(dimension: 17, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.add_shopping_cart_rounded),
                      label: Text(_adding ? 'Menambahkan…' : _outOfStock ? 'Stok habis' : 'Tambah ke Keranjang'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CustomerCart extends ConsumerStatefulWidget {
  const CustomerCart({super.key, required this.onContinueShopping});

  final VoidCallback onContinueShopping;

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
    backgroundColor: const Color(0xFFF7F4F4),
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
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 310),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE7EB),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: const Icon(Icons.shopping_basket_outlined, size: 44, color: Color(0xFFD20A2E)),
                    ),
                    const SizedBox(height: 18),
                    const Text('Keranjang masih kosong',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 21)),
                    const SizedBox(height: 8),
                    const Text('Temukan produk UMKM favoritmu dan tambahkan ke keranjang sebelum checkout.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54, height: 1.45)),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: widget.onContinueShopping,
                        icon: const Icon(Icons.storefront_rounded),
                        label: const Text('Mulai belanja'),
                      ),
                    ),
                  ],
                ),
              ),
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
                    final created = await Navigator.of(context).push<bool>(
                      MaterialPageRoute<bool>(builder: (_) => const CustomerCheckoutPage()),
                    );
                    if (created == true && mounted) await _refresh();
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



class _CmsHeroCarousel extends StatefulWidget {
  const _CmsHeroCarousel({required this.slides, required this.apiBase});

  final List<dynamic> slides;
  final String apiBase;

  @override
  State<_CmsHeroCarousel> createState() => _CmsHeroCarouselState();
}

class _CmsHeroCarouselState extends State<_CmsHeroCarousel> {
  final PageController _controller = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant _CmsHeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slides.length != widget.slides.length) {
      _index = 0;
      if (_controller.hasClients) _controller.jumpToPage(0);
    }
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.slides.length < 2) return;
    _timer = Timer.periodic(const Duration(milliseconds: 6500), (_) {
      if (!mounted || !_controller.hasClients || widget.slides.length < 2) return;
      final next = (_index + 1) % widget.slides.length;
      _controller.animateToPage(next, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    });
  }

  double _ratio(Map<String, dynamic> slide) {
    final ratio = double.tryParse(slide['media_ratio']?.toString() ?? '');
    if (ratio != null && ratio > 0) return ratio;
    final width = double.tryParse(slide['media_width']?.toString() ?? '');
    final height = double.tryParse(slide['media_height']?.toString() ?? '');
    if (width != null && height != null && width > 0 && height > 0) return width / height;
    return 2.0;
  }

  Future<void> _openTarget(String raw) async {
    final target = raw.trim();
    if (target.isEmpty) return;
    final candidate = Uri.tryParse(target);
    final uri = candidate != null && candidate.hasScheme ? candidate : Uri.parse('https://bersolekmart.com').resolve(target);
    if (uri.scheme != 'https' && uri.scheme != 'http') return;
    try {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tautan banner belum dapat dibuka.')));
    }
  }

  Widget _bannerImage(String path, {required BoxFit fit, required double height}) {
    final url = resolveMediaUrl(path, widget.apiBase);
    if (url.isEmpty || url.toLowerCase().split('?').first.endsWith('.svg')) {
      return Container(height: height, alignment: Alignment.center, color: const Color(0xFFF6EDEF),
        child: const Icon(Icons.image_not_supported_outlined, size: 36, color: Color(0xFFB7AEB0)));
    }
    return Image.network(url, height: height, width: double.infinity, fit: fit,
      errorBuilder: (_, _, _) => Container(height: height, alignment: Alignment.center, color: const Color(0xFFF6EDEF),
        child: const Text('Banner tidak dapat dimuat', style: TextStyle(color: Colors.black54))),
      loadingBuilder: (context, child, progress) => progress == null ? child : Container(
        height: height, color: const Color(0xFFF6EDEF), alignment: Alignment.center,
        child: const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.slides.isEmpty) return const SizedBox.shrink();
    final safeIndex = _index.clamp(0, widget.slides.length - 1);
    return Column(children: [
      SizedBox(
        width: double.infinity,
        child: PageView.builder(
          controller: _controller,
          itemCount: widget.slides.length,
          onPageChanged: (value) => setState(() => _index = value),
          itemBuilder: (context, index) {
            final slide = Map<String, dynamic>.from(widget.slides[index] as Map);
            final image = (slide['image_path'] ?? '').toString();
            final ratio = _ratio(slide);
            final wideImage = ratio >= 1.9;
            final height = wideImage ? 175.0 : 190.0;
            final target = (slide['target_url'] ?? '').toString();
            if (wideImage) {
              return Material(
                color: const Color(0xFFF6EDEF), borderRadius: BorderRadius.circular(18), clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: target.trim().isEmpty ? null : () => _openTarget(target),
                  child: AspectRatio(aspectRatio: ratio.clamp(1.45, 2.7).toDouble(), child: _bannerImage(image, fit: BoxFit.contain, height: height)),
                ),
              );
            }
            final title = (slide['title'] ?? '').toString().trim();
            final eyebrow = (slide['eyebrow'] ?? '').toString().trim();
            final subtitle = (slide['subtitle'] ?? slide['body'] ?? '').toString().trim();
            final cta = (slide['cta_label'] ?? '').toString().trim();
            return Container(
              constraints: const BoxConstraints(minHeight: 172),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFD20A2E), Color(0xFF7D0018)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(18)),
              child: Row(children: [
                Expanded(flex: 6, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (eyebrow.isNotEmpty) ...[
                      Text(eyebrow.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
                      const SizedBox(height: 5),
                    ],
                    if (title.isNotEmpty) Text(title, maxLines: 3, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 20, height: 1.13, fontWeight: FontWeight.w900)),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.25)),
                    ],
                    if (cta.isNotEmpty && target.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Align(alignment: Alignment.centerLeft, child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF7D0018), backgroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                        onPressed: () => _openTarget(target),
                        child: Text(cta, style: const TextStyle(fontWeight: FontWeight.w800)))),
                    ],
                  ],
                )),
                const SizedBox(width: 10),
                Expanded(flex: 4, child: ClipRRect(borderRadius: BorderRadius.circular(12),
                  child: SizedBox(height: height - 28, child: _bannerImage(image, fit: BoxFit.contain, height: height - 28)))),
              ]),
            );
          },
        ),
      ),
      if (widget.slides.length > 1) ...[
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: List<Widget>.generate(widget.slides.length, (index) {
          final selected = safeIndex == index;
          return GestureDetector(
            onTap: () => _controller.animateToPage(index, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180), margin: const EdgeInsets.symmetric(horizontal: 3),
              width: selected ? 22 : 7, height: 7,
              decoration: BoxDecoration(color: selected ? const Color(0xFFD20A2E) : const Color(0xFFD8C6CA), borderRadius: BorderRadius.circular(8))));
        })),
      ],
    ]);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
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
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MemberAddressBookPage()));
  }

  void _openBanks(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BankAccountsPage(title: 'Rekening')));
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
