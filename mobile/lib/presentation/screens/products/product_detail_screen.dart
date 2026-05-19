import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/product.dart';
import '../../../domain/entities/transaction.dart';
import '../../providers/auth_provider.dart';
import '../../providers/products_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../widgets/status_badge.dart';
import '../../../core/utils/formatters.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  final String productId;

  const ProductDetailScreen({super.key, required this.productId});

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  final PageController _pageController = PageController();
  int _currentImageIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<String> _getAllImages(Product product) {
    final urls = <String>{};
    if (product.imageUrl != null && product.imageUrl!.isNotEmpty) {
      urls.add(product.imageUrl!);
    }
    for (final img in product.images) {
      if (img.url.isNotEmpty) urls.add(img.url);
    }
    return urls.toList();
  }

  void _openFullScreenViewer(List<String> images, int initialIndex) {
    if (images.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullScreenImageViewer(
          images: images,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);
    final transactionsAsync = ref.watch(transactionsProvider);
    final role = ref.watch(currentUserProvider)?.role ?? UserRole.customer;

    return productsAsync.when(
      data: (products) {
        final product =
            products.where((p) => p.id == widget.productId).firstOrNull;
        if (product == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Product not found')),
          );
        }

        final allImages = _getAllImages(product);
        final productTransactions = transactionsAsync.maybeWhen(
          data: (txs) =>
              txs.where((t) => t.productId == widget.productId).toList(),
          orElse: () => <Transaction>[],
        );

        return Scaffold(
          backgroundColor: AppTheme.backgroundColor(context),
          body: CustomScrollView(
            slivers: [
              // ── Simple Elegant App Bar with Edit Feature ──
              SliverAppBar(
                pinned: true,
                backgroundColor: AppTheme.surfaceColor(context),
                foregroundColor: AppTheme.textPrimary,
                scrolledUnderElevation: 0,
                title: Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                actions: [
                  if (role.canManageProducts)
                    IconButton(
                      icon: Icon(Icons.edit_rounded, color: AppTheme.primary),
                      tooltip: 'Edit Product',
                      onPressed: () =>
                          context.push('/edit-product', extra: product),
                    ),
                  const SizedBox(width: 8),
                ],
              ),

              // ── Content ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── TAPPABLE IMAGE HERO SECTION ──
                      if (allImages.isNotEmpty) ...[
                        GestureDetector(
                          onTap: () => _openFullScreenViewer(
                              allImages, _currentImageIndex),
                          child: Container(
                            height:
                                180, // Compact and highly flexible space-saving height
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusXL),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                PageView.builder(
                                  controller: _pageController,
                                  itemCount: allImages.length,
                                  onPageChanged: (i) =>
                                      setState(() => _currentImageIndex = i),
                                  itemBuilder: (_, i) => CachedNetworkImage(
                                    imageUrl: allImages[i],
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => const Center(
                                      child: CircularProgressIndicator(
                                          color: Colors.white),
                                    ),
                                    errorWidget: (_, __, ___) => Icon(
                                      Icons.broken_image_outlined,
                                      color: Colors.white,
                                      size: 48,
                                    ),
                                  ),
                                ),
                                if (allImages.length > 1)
                                  Positioned(
                                    bottom: 10,
                                    right: 10,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                      child: Text(
                                        '${_currentImageIndex + 1}/${allImages.length}',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  top: 10,
                                  right: 10,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: const BoxDecoration(
                                      color: Colors.black38,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.fullscreen_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // ── Image Thumbnails Row (Tied to Hero) ──
                        if (allImages.length > 1) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 46,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: allImages.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (_, i) => GestureDetector(
                                onTap: () {
                                  _pageController.animateToPage(
                                    i,
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  );
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _currentImageIndex == i
                                          ? AppTheme.primary
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: CachedNetworkImage(
                                      imageUrl: allImages[i],
                                      fit: BoxFit.cover,
                                      placeholder: (_, __) =>
                                          Container(color: Colors.grey[200]),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                      ],

                      // Category Tag Row
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryLight,
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusSM),
                            ),
                            child: Text(
                              product.category.toUpperCase(),
                              style: TextStyle(
                                color: AppTheme.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 1. BIG Product Code (First)
                      Text(
                        product.code,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                          color: AppTheme.primaryTextColor(context),
                        ),
                      ),
                      const SizedBox(height: 4),

                      // 2. Product Name/Title (Small, under the code)
                      Text(
                        product.name,
                        style: TextStyle(
                          color: AppTheme.secondaryTextColor(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (product.description != null &&
                          product.description!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          product.description!,
                          style: TextStyle(
                            color: AppTheme.secondaryTextColor(context),
                            height: 1.5,
                            fontSize: 13,
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      // ── Stock Card ──
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppTheme.primary, AppTheme.primaryDark],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusXL),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withValues(alpha: 0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Available Stock',
                                    style: TextStyle(
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13)),
                                StatusBadge(status: product.stockStatus),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          AppFormatters.formatQuantity(product.quantity, product.pcsPerCarton),
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 36,
                                              fontWeight: FontWeight.w900,
                                              height: 1),
                                        ),
                                      ),
                                      if (product.pcsPerCarton != null && product.pcsPerCarton! > 1) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          '(${product.quantity} total pcs, ${product.pcsPerCarton} per ctn)',
                                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Divider(color: Colors.white24, height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _miniStat('Threshold', '${product.threshold}'),
                                _miniStat('Cost',
                                    '₹${product.costPrice?.toStringAsFixed(0) ?? '0'}'),
                                _miniStat('Price',
                                    '₹${product.price.toStringAsFixed(0)}'),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // ── Stock Action Buttons ──
                      if (role.canRecordStock) ...[
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => context.push(
                                    '/stock-entry?productId=${product.id}&type=out'),
                                icon:
                                    Icon(Icons.remove_circle_rounded, size: 18),
                                label: Text('STOCK OUT'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.danger,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(48),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          AppTheme.radiusMD)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => context.push(
                                    '/stock-entry?productId=${product.id}&type=in'),
                                icon: Icon(Icons.add_circle_rounded, size: 18),
                                label: Text('STOCK IN'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.success,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(48),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          AppTheme.radiusMD)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 24),

                      // ── Color Stock Section (Color Stock matching Admin) ──
                      Text(
                        'Color Stock',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppTheme.primaryTextColor(context),
                        ),
                      ),
                      const SizedBox(height: 10),
                      product.colorStocks.isEmpty
                          ? Container(
                              padding: const EdgeInsets.all(16),
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceColor(context),
                                borderRadius:
                                    BorderRadius.circular(AppTheme.radiusLG),
                                border: Border.all(
                                    color: AppTheme.borderColor(context)),
                              ),
                              child: Text(
                                'No color-wise stock added.',
                                style: TextStyle(
                                    color: AppTheme.mutedTextColor(context),
                                    fontSize: 13),
                              ),
                            )
                          : Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: product.colorStocks.map((entry) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surfaceColor(context),
                                    borderRadius: BorderRadius.circular(
                                        AppTheme.radiusLG),
                                    border: Border.all(
                                        color: AppTheme.borderColor(context)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: _resolveColor(entry.color),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        entry.color,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                          color: AppTheme.primaryTextColor(
                                              context),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryLight,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          AppFormatters.formatQuantity(entry.quantity, product.pcsPerCarton),
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                            color: AppTheme.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),

                      const SizedBox(height: 24),

                      // ── Recent Activity ──
                      Text('Recent History',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 10),
                      if (productTransactions.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(24),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceColor(context),
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusLG),
                            border: Border.all(
                                color: AppTheme.borderColor(context)),
                          ),
                          child: Text('No movements recorded yet',
                              style: TextStyle(
                                  color: AppTheme.mutedTextColor(context))),
                        )
                      else
                        ...productTransactions
                            .take(8)
                            .map((tx) => _ActivityTile(tx: tx)),

                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // ── FAB: Quick Stock Entry ──
          floatingActionButton: role.canRecordStock
              ? FloatingActionButton.extended(
                  onPressed: () => _showStockEntrySheet(context, product),
                  icon: Icon(Icons.add_rounded),
                  label: Text('Stock Entry',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                )
              : null,
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, _) => Scaffold(body: Center(child: Text('Error: $err'))),
    );
  }

  Color _resolveColor(String colorName) {
    final lower = colorName.trim().toLowerCase();
    if (lower == 'red') return Colors.red;
    if (lower == 'blue') return Colors.blue;
    if (lower == 'green') return Colors.green;
    if (lower == 'yellow') return Colors.yellow;
    if (lower == 'orange') return Colors.orange;
    if (lower == 'black') return Colors.black;
    if (lower == 'white') return Colors.grey.shade300;
    if (lower == 'grey' || lower == 'gray') return Colors.grey;
    if (lower == 'purple') return Colors.purple;
    if (lower == 'pink') return Colors.pink;
    if (lower == 'brown') return Colors.brown;
    return AppTheme.primary; // fallback accent color
  }

  Widget _miniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: Colors.white60,
                fontSize: 10,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14)),
      ],
    );
  }

  void _showStockEntrySheet(BuildContext context, Product product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(12),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor(context),
          borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stock Entry – ${product.name}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      context.push(
                          '/stock-entry?productId=${product.id}&type=out');
                    },
                    icon: Icon(Icons.remove_rounded, size: 18),
                    label: Text('STOCK OUT'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.danger,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      context
                          .push('/stock-entry?productId=${product.id}&type=in');
                    },
                    icon: Icon(Icons.add_rounded, size: 18),
                    label: Text('STOCK IN'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Full Screen Image Viewer with Zoom, Download & Share ───
class FullScreenImageViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const FullScreenImageViewer({
    super.key,
    required this.images,
    required this.initialIndex,
  });

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  late PageController _pageController;
  late int _currentIndex;
  bool _isDownloading = false;
  bool _isSharing = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
    _currentIndex = widget.initialIndex;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _downloadImage() async {
    setState(() => _isDownloading = true);
    try {
      final url = widget.images[_currentIndex];
      final name = 'product_img_${DateTime.now().millisecondsSinceEpoch}';
      final response = await http.get(Uri.parse(url));
      final bytes = response.bodyBytes;

      Directory? dir;
      if (Platform.isAndroid) {
        dir = Directory('/storage/emulated/0/Download');
        if (!await dir.exists()) {
          dir = await getExternalStorageDirectory();
        }
      } else {
        dir = await getApplicationDocumentsDirectory();
      }

      final file = File('${dir!.path}/$name.jpg');
      await file.writeAsBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to Downloads: ${file.path.split('/').last}'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _shareImage() async {
    setState(() => _isSharing = true);
    try {
      final url = widget.images[_currentIndex];
      final response = await http.get(Uri.parse(url));
      final bytes = response.bodyBytes;

      final temp = await getTemporaryDirectory();
      final file = File('${temp.path}/share_image.jpg');
      await file.writeAsBytes(bytes);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'B2B Product Image',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sharing failed: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        scrolledUnderElevation: 0,
        title: Text(
          '${_currentIndex + 1} / ${widget.images.length}',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: _isDownloading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : Icon(Icons.download_rounded, color: Colors.white),
            onPressed: _isDownloading ? null : _downloadImage,
          ),
          IconButton(
            icon: _isSharing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : Icon(Icons.share_rounded, color: Colors.white),
            onPressed: _isSharing ? null : _shareImage,
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.images.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemBuilder: (context, index) {
          return InteractiveViewer(
            clipBehavior: Clip.none,
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: CachedNetworkImage(
                imageUrl: widget.images[index],
                fit: BoxFit.contain,
                placeholder: (context, url) =>
                    const CircularProgressIndicator(color: Colors.white),
                errorWidget: (context, url, error) =>
                    Icon(Icons.broken_image, color: Colors.white, size: 64),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Activity Tile ───────────────────────────────────────────
class _ActivityTile extends StatelessWidget {
  final Transaction tx;
  const _ActivityTile({required this.tx});

  @override
  Widget build(BuildContext context) {
    final isIn = tx.isStockIn;
    final color = isIn ? AppTheme.success : AppTheme.danger;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isIn ? Icons.south_west_rounded : Icons.north_east_rounded,
              color: color,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${isIn ? 'Stock In' : 'Stock Out'}: ${AppFormatters.formatQuantity(tx.quantity, tx.pcsPerCarton)}',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  '${tx.workerName.isEmpty ? 'Worker' : tx.workerName} • ${DateFormat('MMM d, h:mm a').format(tx.createdAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppTheme.secondaryTextColor(context),
                      fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            '${isIn ? '+' : '-'}${AppFormatters.formatQuantity(tx.quantity, tx.pcsPerCarton)}',
            style: TextStyle(
                color: color, fontWeight: FontWeight.w800, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
