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
import '../../../domain/entities/product.dart';
import '../../../domain/entities/transaction.dart';
import '../../providers/products_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../widgets/status_badge.dart';

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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenImageViewer(
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

    return productsAsync.when(
      data: (products) {
        final product = products
            .where((p) => p.id == widget.productId)
            .firstOrNull;
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
          backgroundColor: AppTheme.background,
          body: CustomScrollView(
            slivers: [
              // ── Simple Elegant App Bar ──
              SliverAppBar(
                pinned: true,
                backgroundColor: AppTheme.surface,
                foregroundColor: AppTheme.textPrimary,
                scrolledUnderElevation: 0,
                title: Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),

              // ── Content ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category + SKU info row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                              style: const TextStyle(
                                color: AppTheme.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(
                            'SKU: ${product.code}',
                            style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Product Title + Description
                      Text(
                        product.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if (product.description != null &&
                          product.description!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          product.description!,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
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
                            colors: [
                              AppTheme.primary,
                              AppTheme.primaryDark
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusXL),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary
                                  .withValues(alpha: 0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Available Stock',
                                    style: TextStyle(
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13)),
                                StatusBadge(
                                    status: product.stockStatus),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.end,
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '${product.quantity}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 44,
                                        fontWeight: FontWeight.w900,
                                        height: 1),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 6),
                                  child: Text(
                                    product.unit ?? 'Units',
                                    style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 16),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(
                                color: Colors.white24, height: 24),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                _miniStat('Threshold',
                                    '${product.threshold}'),
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
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => context.push(
                                  '/stock-entry?productId=${product.id}&type=out'),
                              icon: const Icon(
                                  Icons.remove_circle_rounded,
                                  size: 18),
                              label: const Text('STOCK OUT'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.danger,
                                foregroundColor: Colors.white,
                                minimumSize:
                                    const Size.fromHeight(48),
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
                              icon: const Icon(
                                  Icons.add_circle_rounded,
                                  size: 18),
                              label: const Text('STOCK IN'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.success,
                                foregroundColor: Colors.white,
                                minimumSize:
                                    const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                        AppTheme.radiusMD)),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // ── NEW Images Section (Moved Down After Stock Entry) ──
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Product Gallery',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          if (allImages.isNotEmpty)
                            TextButton.icon(
                              onPressed: () => _openFullScreenViewer(
                                  allImages, _currentImageIndex),
                              icon: const Icon(Icons.fullscreen_rounded,
                                  size: 18),
                              label: const Text(
                                'Fullscreen',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      allImages.isEmpty
                          ? Container(
                              height: 120,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: AppTheme.surface,
                                borderRadius:
                                    BorderRadius.circular(AppTheme.radiusLG),
                                border:
                                    Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.image_not_supported_outlined,
                                        color: AppTheme.textMuted, size: 36),
                                    SizedBox(height: 8),
                                    Text(
                                      'No images available',
                                      style: TextStyle(
                                          color: AppTheme.textMuted,
                                          fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : Column(
                              children: [
                                Container(
                                  height: 200,
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.circular(
                                        AppTheme.radiusLG),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      PageView.builder(
                                        controller: _pageController,
                                        itemCount: allImages.length,
                                        onPageChanged: (i) => setState(
                                            () => _currentImageIndex = i),
                                        itemBuilder: (_, i) => GestureDetector(
                                          onTap: () => _openFullScreenViewer(
                                              allImages, i),
                                          child: CachedNetworkImage(
                                            imageUrl: allImages[i],
                                            fit: BoxFit.cover,
                                            placeholder: (_, __) => const Center(
                                                child:
                                                    CircularProgressIndicator(
                                                        color: Colors.white)),
                                            errorWidget: (_, __, ___) =>
                                                const Icon(
                                                    Icons
                                                        .broken_image_outlined,
                                                    color: Colors.white),
                                          ),
                                        ),
                                      ),
                                      // Image Index Overlay badge
                                      Positioned(
                                        bottom: 12,
                                        right: 12,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.black54,
                                            borderRadius:
                                                BorderRadius.circular(99),
                                          ),
                                          child: Text(
                                            '${_currentImageIndex + 1}/${allImages.length}',
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (allImages.length > 1) ...[
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    height: 52,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: allImages.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(width: 8),
                                      itemBuilder: (_, i) => GestureDetector(
                                        onTap: () {
                                          _pageController.animateToPage(
                                            i,
                                            duration: const Duration(
                                                milliseconds: 300),
                                            curve: Curves.easeInOut,
                                          );
                                        },
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                              milliseconds: 200),
                                          width: 52,
                                          height: 52,
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                              color: _currentImageIndex == i
                                                  ? AppTheme.primary
                                                  : Colors.transparent,
                                              width: 2,
                                            ),
                                          ),
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            child: CachedNetworkImage(
                                              imageUrl: allImages[i],
                                              fit: BoxFit.cover,
                                              placeholder: (_, __) => Container(
                                                  color: Colors.grey[200]),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),

                      const SizedBox(height: 24),

                      // ── NEW Colors Section (Color Stock matching Admin) ──
                      const Text(
                        'Color Stock',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      product.colorStocks.isEmpty
                          ? Container(
                              padding: const EdgeInsets.all(16),
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: AppTheme.surface,
                                borderRadius:
                                    BorderRadius.circular(AppTheme.radiusLG),
                                border:
                                    Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: const Text(
                                'No color-wise stock added.',
                                style: TextStyle(
                                    color: AppTheme.textMuted, fontSize: 13),
                              ),
                            )
                          : GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 2.8,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                              itemCount: product.colorStocks.length,
                              itemBuilder: (context, index) {
                                final entry = product.colorStocks[index];
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surface,
                                    borderRadius: BorderRadius.circular(
                                        AppTheme.radiusMD),
                                    border: Border.all(
                                        color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      // Left: color name + small circle
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: _resolveColor(
                                                    entry.color),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                entry.color,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                  color: AppTheme.textPrimary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Right: Quantity
                                      Text(
                                        '${entry.quantity}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                          color: AppTheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),

                      const SizedBox(height: 24),

                      // ── Recent Activity ──
                      const Text('Recent History',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16)),
                      const SizedBox(height: 10),
                      if (productTransactions.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(24),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(
                                AppTheme.radiusLG),
                            border: Border.all(
                                color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Text(
                              'No movements recorded yet',
                              style: TextStyle(
                                  color: AppTheme.textMuted)),
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
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showStockEntrySheet(context, product),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Stock Entry',
                style: TextStyle(fontWeight: FontWeight.w700)),
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
          ),
        );
      },
      loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator())),
      error: (err, _) =>
          Scaffold(body: Center(child: Text('Error: $err'))),
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
            style: const TextStyle(
                color: Colors.white60,
                fontSize: 10,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
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
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stock Entry – ${product.name}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 16)),
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
                    icon: const Icon(Icons.remove_rounded, size: 18),
                    label: const Text('STOCK OUT'),
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
                      context.push(
                          '/stock-entry?productId=${product.id}&type=in');
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('STOCK IN'),
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

// ─── NEW Full Screen Image Viewer with Zoom, Download & Share ───
class _FullScreenImageViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const _FullScreenImageViewer({
    required this.images,
    required this.initialIndex,
  });

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
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
            content: Text(
                'Saved to Downloads: ${file.path.split('/').last}'),
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

      await Share.shareXFiles([XFile(file.path)], text: 'B2B Product Image');
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
          style: const TextStyle(color: Colors.white, fontSize: 16),
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
                : const Icon(Icons.download_rounded, color: Colors.white),
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
                : const Icon(Icons.share_rounded, color: Colors.white),
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
                errorWidget: (context, url, error) => const Icon(
                    Icons.broken_image,
                    color: Colors.white,
                    size: 64),
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
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
              isIn
                  ? Icons.south_west_rounded
                  : Icons.north_east_rounded,
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
                  '${isIn ? 'Stock In' : 'Stock Out'}: ${tx.quantity} units',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  '${tx.workerName.isEmpty ? 'Worker' : tx.workerName} • ${DateFormat('MMM d, h:mm a').format(tx.createdAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            '${isIn ? '+' : '-'}${tx.quantity}',
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 14),
          ),
        ],
      ),
    );
  }
}
