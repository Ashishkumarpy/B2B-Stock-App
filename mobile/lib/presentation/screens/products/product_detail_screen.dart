import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/product.dart';
import '../../../domain/entities/transaction.dart';
import '../../providers/products_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../widgets/app_network_image.dart';
import '../../widgets/status_badge.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  final String productId;

  const ProductDetailScreen({
    super.key,
    required this.productId,
  });

  @override
  ConsumerState<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  int _currentImageIndex = 0;

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);
    final transactionsAsync = ref.watch(transactionsProvider);

    return productsAsync.when(
      data: (products) {
        final product = products.where((p) => p.id == widget.productId).firstOrNull;
        if (product == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Product not found')),
          );
        }

        final productTransactions = transactionsAsync.maybeWhen(
          data: (txs) => txs.where((t) => t.productId == widget.productId).toList(),
          orElse: () => <Transaction>[],
        );

        return Scaffold(
          body: CustomScrollView(
            slivers: [
              _buildAppBar(context, product),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.sp24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(context, product),
                      const SizedBox(height: AppTheme.sp32),
                      _buildStockCard(context, product),
                      const SizedBox(height: AppTheme.sp32),
                      _buildActions(context, product),
                      const SizedBox(height: AppTheme.sp32),
                      _buildDetailsGrid(product),
                      const SizedBox(height: AppTheme.sp32),
                      _buildRecentActivity(context, productTransactions),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, _) => Scaffold(body: Center(child: Text('Error: $err'))),
    );
  }

  Widget _buildAppBar(BuildContext context, Product product) {
    final allImages = product.images.isNotEmpty 
        ? product.images.map((e) => e.url).toList() 
        : (product.imageUrl != null ? [product.imageUrl!] : []);

    return SliverAppBar(
      expandedHeight: 350,
      pinned: true,
      backgroundColor: Colors.black,
      flexibleSpace: FlexibleSpaceBar(
        background: allImages.isEmpty
            ? Container(color: Colors.grey[200], child: const Icon(Icons.inventory_2_outlined, size: 64))
            : Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    itemCount: allImages.length,
                    onPageChanged: (index) => setState(() => _currentImageIndex = index),
                    itemBuilder: (context, index) {
                      return AppNetworkImage(imageUrl: allImages[index], fit: BoxFit.cover);
                    },
                  ),
                  if (allImages.length > 1)
                    Positioned(
                      bottom: 16,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: allImages.asMap().entries.map((entry) {
                          return Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(_currentImageIndex == entry.key ? 0.9 : 0.4),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Product product) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppTheme.radiusSM),
              ),
              child: Text(
                product.category.toUpperCase(),
                style: const TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
            Text(
              'SKU: ${product.code}',
              style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.sp12),
        Text(
          product.name,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5),
        ),
        if (product.description != null && product.description!.isNotEmpty) ...[
          const SizedBox(height: AppTheme.sp8),
          Text(
            product.description!,
            style: TextStyle(color: Colors.grey.shade600, height: 1.5),
          ),
        ],
      ],
    );
  }

  Widget _buildStockCard(BuildContext context, Product product) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.sp24),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.25),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Available Stock', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              StatusBadge(status: product.stockStatus),
            ],
          ),
          const SizedBox(height: AppTheme.sp12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${product.quantity}',
                style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w900),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  product.unit ?? 'Units',
                  style: const TextStyle(color: Colors.white60, fontSize: 18, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white24, height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMiniStat('Alert Threshold', '${product.threshold}'),
              _buildMiniStat('Buying Price', '₹${product.costPrice ?? 0}'),
              _buildMiniStat('Selling Price', '₹${product.price}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
      ],
    );
  }

  Widget _buildActions(BuildContext context, Product product) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => context.push('/stock-entry?productId=${product.id}&type=out'),
            icon: const Icon(Icons.remove_circle_rounded),
            label: const Text('STOCK OUT'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(60),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLG)),
            ),
          ),
        ),
        const SizedBox(width: AppTheme.sp16),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => context.push('/stock-entry?productId=${product.id}&type=in'),
            icon: const Icon(Icons.add_circle_rounded),
            label: const Text('STOCK IN'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.success,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(60),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLG)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsGrid(Product product) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Product Details', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        const SizedBox(height: 16),
        _buildDetailRow('Manufacturer', 'StockIQ Global'),
        _buildDetailRow('Storage Zone', 'Zone A-42'),
        _buildDetailRow('Weight/Vol', '2.5 kg'),
        _buildDetailRow('Last Synced', DateFormat('MMM d, yyyy HH:mm').format(product.updatedAt ?? DateTime.now())),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildRecentActivity(BuildContext context, List<Transaction> transactions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Recent History', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            TextButton(onPressed: () {}, child: const Text('View All')),
          ],
        ),
        const SizedBox(height: 8),
        if (transactions.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Text('No recent movements recorded', style: TextStyle(color: Colors.grey))),
          )
        else
          ...transactions.take(5).map((tx) => _ActivityTile(tx: tx)),
      ],
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final Transaction tx;
  const _ActivityTile({required this.tx});

  @override
  Widget build(BuildContext context) {
    final isStockIn = tx.type == TransactionType.stockIn;
    final color = isStockIn ? AppTheme.success : AppTheme.danger;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
        child: Icon(isStockIn ? Icons.south_west_rounded : Icons.north_east_rounded, color: color, size: 18),
      ),
      title: Text(
        '${isStockIn ? 'Stock In' : 'Stock Out'}: ${tx.quantity} units',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
      subtitle: Text('${tx.workerName.isEmpty ? 'Worker' : tx.workerName} • ${DateFormat('MMM d, h:mm a').format(tx.createdAt)}'),
      trailing: const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
    );
  }
}
