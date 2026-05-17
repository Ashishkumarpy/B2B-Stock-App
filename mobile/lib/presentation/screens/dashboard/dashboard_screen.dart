import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
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

    final lowStockCount = productsAsync.maybeWhen(
      data: (p) => p.where((x) => x.stockStatus == StockStatus.lowStock).length,
      orElse: () => 0,
    );

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
                Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_none_rounded,
                          color: AppTheme.textPrimary),
                      onPressed: () => _showNotificationsBottomSheet(context),
                    ),
                    if (lowStockCount > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: AppTheme.danger,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 8,
                            minHeight: 8,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 4),
              ],
            ),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Stats Row
                  _buildStatsSection(productsAsync, transactionsAsync),
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

  Widget _buildStatsSection(
    AsyncValue<List<dynamic>> productsAsync,
    AsyncValue<List<dynamic>> transactionsAsync,
  ) {
    final totalProducts = productsAsync.maybeWhen(
      data: (p) => p.length,
      orElse: () => 0,
    );
    final availableStock = productsAsync.maybeWhen(
      data: (p) => p.fold<int>(0, (s, x) => s + (x.quantity as int)),
      orElse: () => 0,
    );
    final now = DateTime.now();
    final stockIn = transactionsAsync.maybeWhen(
      data: (txs) => txs
          .where((t) => t.isStockIn == true &&
              t.createdAt.year == now.year &&
              t.createdAt.month == now.month &&
              t.createdAt.day == now.day)
          .fold<int>(0, (s, t) => s + (t.quantity as int)),
      orElse: () => 0,
    );
    final stockOut = transactionsAsync.maybeWhen(
      data: (txs) => txs
          .where((t) => t.isStockOut == true &&
              t.createdAt.year == now.year &&
              t.createdAt.month == now.month &&
              t.createdAt.day == now.day)
          .fold<int>(0, (s, t) => s + (t.quantity as int)),
      orElse: () => 0,
    );

    final isLoading = productsAsync is AsyncLoading ||
        transactionsAsync is AsyncLoading;

    if (isLoading) {
      return Column(
        children: [
          Row(children: [
            Expanded(child: SkeletonLoading(width: double.infinity, height: 88)),
            const SizedBox(width: 12),
            Expanded(child: SkeletonLoading(width: double.infinity, height: 88)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: SkeletonLoading(width: double.infinity, height: 88)),
            const SizedBox(width: 12),
            Expanded(child: SkeletonLoading(width: double.infinity, height: 88)),
          ]),
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Total Products',
                value: '$totalProducts',
                icon: Icons.inventory_2_rounded,
                color: AppTheme.primary,
                onTap: () => context.go('/products'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Available Stock',
                value: '$availableStock',
                icon: Icons.layers_rounded,
                color: AppTheme.success,
                onTap: () => context.go('/products?filter=in_stock'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Stock In (Today)',
                value: '+$stockIn',
                icon: Icons.south_west_rounded,
                color: AppTheme.success,
                onTap: () => context.push('/stock-activity?type=stockIn&dateMode=today'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Stock Out (Today)',
                value: '-$stockOut',
                icon: Icons.north_east_rounded,
                color: AppTheme.danger,
                onTap: () => context.push('/stock-activity?type=stockOut&dateMode=today'),
              ),
            ),
          ],
        ),
      ],
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
              height: 112,
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
              width: double.infinity, height: 112),
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

  void _showNotificationsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Consumer(
              builder: (context, ref, _) {
                final productsAsync = ref.watch(productsProvider);
                final transactionsAsync = ref.watch(transactionsProvider);

                final lowStockProds = productsAsync.maybeWhen(
                  data: (p) => p.where((x) => x.stockStatus == StockStatus.lowStock).toList(),
                  orElse: () => [],
                );

                final recentTxs = transactionsAsync.maybeWhen(
                  data: (txs) => txs.take(15).toList(),
                  orElse: () => [],
                );

                return Container(
                  decoration: const BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(AppTheme.radiusXL),
                      topRight: Radius.circular(AppTheme.radiusXL),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Header drag bar
                      const SizedBox(height: 8),
                      Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Title
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Notifications & Alerts',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            if (lowStockProds.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.danger.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${lowStockProds.length} Alerts',
                                  style: const TextStyle(
                                    color: AppTheme.danger,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Custom Tab List
                      Expanded(
                        child: DefaultTabController(
                          length: 2,
                          child: Column(
                            children: [
                              TabBar(
                                indicatorColor: AppTheme.primary,
                                labelColor: AppTheme.primary,
                                unselectedLabelColor: AppTheme.textSecondary,
                                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                tabs: const [
                                  Tab(text: '🚨 Critical Alerts'),
                                  Tab(text: '📝 Activity Log'),
                                ],
                              ),
                              Expanded(
                                child: TabBarView(
                                  children: [
                                    // 1. Alerts View
                                    _buildAlertsTab(lowStockProds, scrollController),
                                    // 2. Activity Log View
                                    _buildActivityTab(recentTxs, scrollController),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildAlertsTab(List<dynamic> lowStockProds, ScrollController scrollController) {
    if (lowStockProds.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline_rounded, color: AppTheme.success, size: 48),
            const SizedBox(height: 12),
            const Text(
              'All Systems Healthy',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              'No items are currently below stock threshold.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: lowStockProds.length,
      itemBuilder: (context, index) {
        final product = lowStockProds[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusLG),
            side: BorderSide(color: AppTheme.danger.withValues(alpha: 0.15)),
          ),
          color: AppTheme.danger.withValues(alpha: 0.02),
          child: InkWell(
            onTap: () {
              Navigator.pop(context); // Close bottom sheet
              context.push('/products?filter=low');
            },
            borderRadius: BorderRadius.circular(AppTheme.radiusLG),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.warning_rounded, color: AppTheme.danger, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.code,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          product.name,
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              'Stock: ${product.quantity}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.danger),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Threshold: ${product.threshold}',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppTheme.textMuted),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActivityTab(List<dynamic> recentTxs, ScrollController scrollController) {
    if (recentTxs.isEmpty) {
      return const Center(
        child: Text('No recent transaction activity.', style: TextStyle(color: AppTheme.textSecondary)),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: recentTxs.length,
      itemBuilder: (context, index) {
        final tx = recentTxs[index];
        final isStockIn = tx.isStockIn;
        final timeStr = _formatTimeAgo(tx.createdAt);

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusLG),
            side: BorderSide(color: Colors.grey.withValues(alpha: 0.12)),
          ),
          child: InkWell(
            onTap: () {
              Navigator.pop(context); // Close bottom sheet
              context.push('/stock-activity');
            },
            borderRadius: BorderRadius.circular(AppTheme.radiusLG),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (isStockIn ? AppTheme.success : AppTheme.danger).withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isStockIn ? Icons.south_west_rounded : Icons.north_east_rounded,
                      color: isStockIn ? AppTheme.success : AppTheme.danger,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tx.productCode ?? 'UNKNOWN',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${isStockIn ? "Stocked In" : "Stocked Out"}: ${tx.quantity} units',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        if (tx.workerName != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'By: ${tx.workerName}',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        timeStr,
                        style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
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
