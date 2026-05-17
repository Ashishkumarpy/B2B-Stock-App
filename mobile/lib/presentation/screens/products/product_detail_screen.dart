import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
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

class _ProductDetailScreenState
    extends ConsumerState<ProductDetailScreen> {
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
              // ── Image App Bar ──
              SliverAppBar(
                expandedHeight: 280,
                pinned: true,
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                flexibleSpace: FlexibleSpaceBar(
                  background: allImages.isEmpty
                      ? Container(
                          color: AppTheme.primaryLight,
                          child: const Center(
                            child: Icon(Icons.inventory_2_outlined,
                                size: 72, color: AppTheme.primary),
                          ),
                        )
                      : Stack(
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
                                placeholder: (_, __) => Container(
                                    color: AppTheme.primaryLight),
                                errorWidget: (_, __, ___) => Container(
                                  color: AppTheme.primaryLight,
                                  child: const Icon(
                                      Icons.broken_image_outlined,
                                      color: AppTheme.primary),
                                ),
                              ),
                            ),
                            // Page dots
                            if (allImages.length > 1)
                              Positioned(
                                bottom: 12,
                                left: 0,
                                right: 0,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: List.generate(
                                    allImages.length,
                                    (i) => AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      width: _currentImageIndex == i ? 20 : 6,
                                      height: 6,
                                      margin:
                                          const EdgeInsets.symmetric(horizontal: 3),
                                      decoration: BoxDecoration(
                                        color: _currentImageIndex == i
                                            ? Colors.white
                                            : Colors.white54,
                                        borderRadius:
                                            BorderRadius.circular(3),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            // Image counter badge
                            if (allImages.length > 1)
                              Positioned(
                                top: kToolbarHeight + 8,
                                right: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius:
                                        BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    '${_currentImageIndex + 1}/${allImages.length}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ),

              // ── Image Thumbnails Row ──
              if (allImages.length > 1)
                SliverToBoxAdapter(
                  child: Container(
                    height: 64,
                    color: Colors.black,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      itemCount: allImages.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: 8),
                      itemBuilder: (_, i) => GestureDetector(
                        onTap: () {
                          _pageController.animateToPage(i,
                              duration:
                                  const Duration(milliseconds: 300),
                              curve: Curves.easeInOut);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 48,
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
                              placeholder: (_, __) => Container(
                                  color: Colors.grey[900]),
                            ),
                          ),
                        ),
                      ),
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
                      // Category + SKU
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
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

                      // Product Name
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
                                _MiniStat('Threshold',
                                    '${product.threshold}'),
                                _MiniStat('Cost',
                                    '₹${product.costPrice?.toStringAsFixed(0) ?? '0'}'),
                                _MiniStat('Price',
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

                      const SizedBox(height: 20),

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

  Widget _MiniStat(String label, String value) {
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
