import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/version_check_service.dart';
import '../../providers/products_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../providers/categories_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/skeleton_loading.dart';
import '../../widgets/stock_chart_widget.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      VersionCheckService.check(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);
    final transactionsAsync = ref.watch(transactionsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final user = ref.watch(authStateProvider).user;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        color: AppTheme.primary,
        onRefresh: () async {
          ref.invalidate(productsProvider);
          ref.invalidate(transactionsProvider);
          ref.invalidate(categoriesProvider);
        },
        child: CustomScrollView(
          slivers: [
            // Compact AppBar — no giant user section
            SliverAppBar(
              floating: true,
              snap: true,
              backgroundColor: AppTheme.surface,
              elevation: 0,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Good ${_greeting()},',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500),
                  ),
                  Text(
                    user?.name ?? 'Admin',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.notifications_none_rounded,
                      color: AppTheme.textPrimary),
                  onPressed: () {},
                ),
                const SizedBox(width: 4),
              ],
            ),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Stats Row
                  _buildStatsSection(productsAsync),
                  const SizedBox(height: 20),

                  // Quick Actions
                  _buildQuickActions(),
                  const SizedBox(height: 20),

                  // Stock Movement Chart
                  _buildChartSection(transactionsAsync),
                  const SizedBox(height: 20),

                  // Category Folders
                  _buildFoldersSection(categoriesAsync, productsAsync),
                  const SizedBox(height: 20),

                  // Recent Transactions
                  _buildRecentActivitySection(transactionsAsync),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Morning';
    if (h < 17) return 'Afternoon';
    return 'Evening';
  }

  Widget _buildStatsSection(AsyncValue<List<dynamic>> productsAsync) {
    return productsAsync.when(
      data: (products) {
        final totalSkus = products.length;
        final totalUnits =
            products.fold<int>(0, (s, p) => s + (p.quantity as int));
        final lowStock =
            products.where((p) => p.quantity <= p.threshold).length;
        final inStock = products
            .where((p) => p.quantity > p.threshold)
            .length;

        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: 'Total SKUs',
                    value: '$totalSkus',
                    icon: Icons.inventory_2_rounded,
                    color: AppTheme.primary,
                    onTap: () => context.go('/products'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    label: 'Total Units',
                    value: '$totalUnits',
                    icon: Icons.layers_rounded,
                    color: AppTheme.success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: 'Low Stock',
                    value: '$lowStock',
                    icon: Icons.warning_amber_rounded,
                    color: AppTheme.warning,
                    onTap: () =>
                        context.go('/products?filter=low'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    label: 'In Stock',
                    value: '$inStock',
                    icon: Icons.check_circle_rounded,
                    color: const Color(0xFF8B5CF6),
                    onTap: () => context.go('/analytics'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
      loading: () => Column(
        children: [
          Row(children: [
            Expanded(
                child: SkeletonLoading(
                    width: double.infinity, height: 90)),
            const SizedBox(width: 12),
            Expanded(
                child: SkeletonLoading(
                    width: double.infinity, height: 90)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: SkeletonLoading(
                    width: double.infinity, height: 90)),
            const SizedBox(width: 12),
            Expanded(
                child: SkeletonLoading(
                    width: double.infinity, height: 90)),
          ]),
        ],
      ),
      error: (err, _) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.dangerLight,
          borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        ),
        child: Text('Error loading stats: $err',
            style: const TextStyle(color: AppTheme.danger)),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Quick Actions',
            style:
                TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _QuickActionBtn(
                label: 'Stock In',
                icon: Icons.add_circle_rounded,
                color: AppTheme.success,
                onTap: () =>
                    context.push('/stock-entry?type=in'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickActionBtn(
                label: 'Stock Out',
                icon: Icons.remove_circle_rounded,
                color: AppTheme.danger,
                onTap: () =>
                    context.push('/stock-entry?type=out'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickActionBtn(
                label: 'Products',
                icon: Icons.inventory_2_rounded,
                color: AppTheme.primary,
                onTap: () => context.go('/products'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickActionBtn(
                label: 'Analytics',
                icon: Icons.bar_chart_rounded,
                color: const Color(0xFF8B5CF6),
                onTap: () => context.go('/analytics'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChartSection(
      AsyncValue<List<dynamic>> transactionsAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Stock Movement',
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 15)),
            TextButton(
              onPressed: () => context.go('/stock-activity'),
              child: const Text('View All',
                  style: TextStyle(
                      color: AppTheme.primary, fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 180,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius:
                BorderRadius.circular(AppTheme.radiusLG),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: transactionsAsync.when(
            data: (txns) =>
                StockChartWidget(transactions: txns.cast()),
            loading: () => const SkeletonLoading(
                width: double.infinity, height: 150),
            error: (_, __) => const Center(
                child: Text('Chart unavailable',
                    style: TextStyle(color: AppTheme.textMuted))),
          ),
        ),
      ],
    );
  }

  Widget _buildFoldersSection(
    AsyncValue<List<String>> categoriesAsync,
    AsyncValue<List<dynamic>> productsAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Folders',
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 15)),
            TextButton(
              onPressed: () => context.go('/products'),
              child: const Text('See All',
                  style: TextStyle(
                      color: AppTheme.primary, fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        categoriesAsync.when(
          data: (categories) {
            if (categories.isEmpty) {
              return const SizedBox.shrink();
            }
            return SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  return _FolderChip(
                    category: categories[index],
                    productsAsync: productsAsync,
                    onTap: () => context.go(
                        '/products?filter=${Uri.encodeComponent(categories[index])}'),
                  );
                },
              ),
            );
          },
          loading: () => const SkeletonLoading(
              width: double.infinity, height: 100),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildRecentActivitySection(
      AsyncValue<List<dynamic>> transactionsAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Recent Activity',
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 15)),
            TextButton(
              onPressed: () => context.go('/stock-activity'),
              child: const Text('View All',
                  style: TextStyle(
                      color: AppTheme.primary, fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        transactionsAsync.when(
          data: (txns) {
            if (txns.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(24),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius:
                      BorderRadius.circular(AppTheme.radiusLG),
                  border:
                      Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Text('No transactions yet',
                    style:
                        TextStyle(color: AppTheme.textMuted)),
              );
            }
            return Column(
              children: txns
                  .take(5)
                  .map<Widget>((txn) => _ActivityRow(txn: txn))
                  .toList(),
            );
          },
          loading: () =>
              const SkeletonList(count: 3, height: 64),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ─── Stat Card ──────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppTheme.radiusLG),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius:
                    BorderRadius.circular(AppTheme.radiusMD),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: color,
                        height: 1,
                      ),
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: color.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Quick Action Button ────────────────────────────────────
class _QuickActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusLG),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Folder Chip ────────────────────────────────────────────
class _FolderChip extends ConsumerWidget {
  final String category;
  final AsyncValue<List<dynamic>> productsAsync;
  final VoidCallback onTap;

  const _FolderChip({
    required this.category,
    required this.productsAsync,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = productsAsync.maybeWhen(
      data: (products) =>
          products.where((p) => p.category == category).length,
      orElse: () => 0,
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 110,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.primaryLight,
          borderRadius: BorderRadius.circular(AppTheme.radiusLG),
          border: Border.all(
              color: AppTheme.primary.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_rounded,
                color: AppTheme.primary, size: 22),
            const SizedBox(height: 6),
            Text(
              category,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: AppTheme.textPrimary,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$count items',
              style: const TextStyle(
                  fontSize: 10, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Activity Row ────────────────────────────────────────────
class _ActivityRow extends StatelessWidget {
  final dynamic txn;
  const _ActivityRow({required this.txn});

  @override
  Widget build(BuildContext context) {
    final isIn = txn.isStockIn as bool? ?? false;
    final color = isIn ? AppTheme.success : AppTheme.danger;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius:
                  BorderRadius.circular(AppTheme.radiusMD),
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
                  txn.productName?.toString().isEmpty == true
                      ? 'Unknown'
                      : txn.productName.toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  txn.workerName?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            '${isIn ? '+' : '-'}${txn.quantity}',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
