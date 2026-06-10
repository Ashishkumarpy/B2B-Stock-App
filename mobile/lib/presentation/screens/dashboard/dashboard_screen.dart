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
import '../../providers/settings_provider.dart';
import '../../providers/warehouse_stock_summary_provider.dart';
import '../../../domain/entities/app_user.dart';
import '../../../domain/entities/product.dart';
import '../../../core/utils/formatters.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final TextEditingController _dashboardSearchController =
      TextEditingController();
  String _dashboardSearchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = ref.read(settingsProvider);
      if (settings.inAppUpdates) {
        VersionCheckService.check(context, ref);
      }
    });
  }

  @override
  void dispose() {
    _dashboardSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);
    final transactionsAsync = ref.watch(transactionsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final warehouseStockSummaryAsync = ref.watch(warehouseStockSummaryProvider);
    final user = ref.watch(authStateProvider).user;

    final lowStockCount = productsAsync.maybeWhen(
      data: (p) => p.where((x) => x.stockStatus == StockStatus.lowStock).length,
      orElse: () => 0,
    );

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor(context),
      body: RefreshIndicator(
        color: AppTheme.primary,
        onRefresh: () async {
          ref.invalidate(productsProvider);
          ref.invalidate(transactionsProvider);
          ref.invalidate(categoriesProvider);
          ref.invalidate(warehouseStockSummaryProvider);
        },
        child: CustomScrollView(
          slivers: [
            // Compact AppBar — no giant user section
            SliverAppBar(
              floating: true,
              snap: true,
              backgroundColor: AppTheme.surfaceColor(context),
              elevation: 0,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Good ${_greeting()},',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.secondaryTextColor(context),
                        fontWeight: FontWeight.w500),
                  ),
                  Text(
                    user?.name ?? 'Admin',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryTextColor(context)),
                  ),
                ],
              ),
              actions: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      icon: Icon(Icons.notifications_none_rounded,
                          color: AppTheme.primaryTextColor(context)),
                      onPressed: () =>
                          _showNotificationsBottomSheet(context, user),
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
                  _buildDashboardSearch(productsAsync),
                  const SizedBox(height: 16),

                  // Stats Row
                  _buildStatsSection(productsAsync, transactionsAsync, user),
                  const SizedBox(height: 20),

                  // Quick Actions
                  _buildQuickActions(user),
                  const SizedBox(height: 20),

                  // Warehouse Stock Dashboard
                  _buildWarehouseStockSection(warehouseStockSummaryAsync),
                  const SizedBox(height: 20),

                  // Stock Movement Chart
                  if (user?.canViewStockActivity == true) ...[
                    _buildChartSection(transactionsAsync),
                    const SizedBox(height: 20),
                  ],

                  // Category Folders
                  _buildFoldersSection(categoriesAsync, productsAsync),
                  const SizedBox(height: 20),

                  // Recent Transactions
                  if (user?.canViewStockActivity == true)
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

  Widget _buildDashboardSearch(AsyncValue<List<dynamic>> productsAsync) {
    final query = _dashboardSearchQuery.trim().toLowerCase();
    final results = query.isEmpty
        ? <Product>[]
        : productsAsync.maybeWhen(
            data: (products) => products
                .whereType<Product>()
                .where((product) {
                  return product.code.toLowerCase().contains(query) ||
                      product.name.toLowerCase().contains(query) ||
                      product.category.toLowerCase().contains(query);
                })
                .take(8)
                .toList(),
            orElse: () => <Product>[],
          );

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Column(
        children: [
          TextField(
            controller: _dashboardSearchController,
            onChanged: (value) {
              setState(() {
                _dashboardSearchQuery = value;
              });
            },
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search products by code or name...',
              prefixIcon: Icon(
                Icons.search_rounded,
                color: AppTheme.mutedTextColor(context),
                size: 20,
              ),
              suffixIcon: _dashboardSearchQuery.isNotEmpty
                  ? IconButton(
                      tooltip: 'Clear search',
                      icon: Icon(
                        Icons.close_rounded,
                        color: AppTheme.mutedTextColor(context),
                        size: 18,
                      ),
                      onPressed: () {
                        _dashboardSearchController.clear();
                        setState(() {
                          _dashboardSearchQuery = '';
                        });
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
          if (query.isNotEmpty) ...[
            Divider(height: 1, color: AppTheme.borderColor(context)),
            if (results.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No matching products',
                  style: TextStyle(
                    color: AppTheme.secondaryTextColor(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              ...results.map((product) {
                return InkWell(
                  onTap: () {
                    FocusScope.of(context).unfocus();
                    context.push('/products/${product.id}');
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.inventory_2_rounded,
                            color: AppTheme.primary,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product.code.isNotEmpty
                                    ? product.code
                                    : 'No Code',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppTheme.primaryTextColor(context),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${product.name} - ${product.category}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppTheme.secondaryTextColor(context),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${product.quantity} pcs',
                          style: TextStyle(
                            color: product.quantity > 0
                                ? AppTheme.success
                                : AppTheme.danger,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ],
      ),
    );
  }

  Widget _buildStatsSection(
    AsyncValue<List<dynamic>> productsAsync,
    AsyncValue<List<dynamic>> transactionsAsync,
    AppUser? user,
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
          .where((t) =>
              t.isStockIn == true &&
              t.createdAt.year == now.year &&
              t.createdAt.month == now.month &&
              t.createdAt.day == now.day)
          .fold<int>(0, (s, t) => s + (t.quantity as int)),
      orElse: () => 0,
    );
    final stockOut = transactionsAsync.maybeWhen(
      data: (txs) => txs
          .where((t) =>
              t.isStockOut == true &&
              t.createdAt.year == now.year &&
              t.createdAt.month == now.month &&
              t.createdAt.day == now.day)
          .fold<int>(0, (s, t) => s + (t.quantity as int)),
      orElse: () => 0,
    );

    final isLoading =
        productsAsync is AsyncLoading || transactionsAsync is AsyncLoading;

    if (isLoading) {
      return Column(
        children: [
          Row(children: [
            Expanded(
                child: SkeletonLoading(width: double.infinity, height: 88)),
            const SizedBox(width: 12),
            Expanded(
                child: SkeletonLoading(width: double.infinity, height: 88)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: SkeletonLoading(width: double.infinity, height: 88)),
            const SizedBox(width: 12),
            Expanded(
                child: SkeletonLoading(width: double.infinity, height: 88)),
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
                onTap: user?.canViewStockActivity == true
                    ? () => context
                        .push('/stock-activity?type=stockIn&dateMode=today')
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Stock Out (Today)',
                value: '-$stockOut',
                icon: Icons.north_east_rounded,
                color: AppTheme.danger,
                onTap: user?.canViewStockActivity == true
                    ? () => context
                        .push('/stock-activity?type=stockOut&dateMode=today')
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActions(AppUser? user) {
    final actions = <Widget>[
      if (user?.canRecordStock == true)
        _QuickActionBtn(
          label: 'Stock In',
          icon: Icons.add_circle_rounded,
          color: AppTheme.success,
          onTap: () => context.push('/stock-entry?type=in'),
        ),
      if (user?.canRecordStock == true)
        _QuickActionBtn(
          label: 'Stock Out',
          icon: Icons.remove_circle_rounded,
          color: AppTheme.danger,
          onTap: () => context.push('/stock-entry?type=out'),
        ),
      if (user?.canRecordStock == true)
        _QuickActionBtn(
          label: 'Shift',
          icon: Icons.swap_horiz_rounded,
          color: AppTheme.primary,
          onTap: () => context.push('/stock-entry?type=shift'),
        ),
      _QuickActionBtn(
        label: 'Products',
        icon: Icons.inventory_2_rounded,
        color: AppTheme.primary,
        onTap: () => context.go('/products'),
      ),
      if (user?.canViewAnalytics == true)
        _QuickActionBtn(
          label: 'Analytics',
          icon: Icons.bar_chart_rounded,
          color: const Color(0xFF8B5CF6),
          onTap: () => context.go('/analytics'),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: actions[i]),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildChartSection(AsyncValue<List<dynamic>> transactionsAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Stock Movement',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            TextButton(
              onPressed: () => context.go('/stock-activity'),
              child: Text('View All',
                  style: TextStyle(color: AppTheme.primary, fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 180,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor(context),
            borderRadius: BorderRadius.circular(AppTheme.radiusLG),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: transactionsAsync.when(
            data: (txns) => StockChartWidget(transactions: txns.cast()),
            loading: () =>
                const SkeletonLoading(width: double.infinity, height: 150),
            error: (_, __) => Center(
                child: Text('Chart unavailable',
                    style: TextStyle(color: AppTheme.mutedTextColor(context)))),
          ),
        ),
      ],
    );
  }

  Widget _buildWarehouseStockSection(
      AsyncValue<List<Map<String, dynamic>>> summaryAsync) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Warehouse Stock',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor(context),
              borderRadius: BorderRadius.circular(AppTheme.radiusLG),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: 'Top Warehouses'),
                    Tab(text: 'All Warehouses'),
                  ],
                ),
                SizedBox(
                  height: 260,
                  child: TabBarView(
                    children: [
                      _buildWarehouseStockTabContent(summaryAsync,
                          topOnly: true),
                      _buildWarehouseStockTabContent(summaryAsync,
                          topOnly: false),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarehouseStockTabContent(
    AsyncValue<List<Map<String, dynamic>>> summaryAsync, {
    required bool topOnly,
  }) {
    return summaryAsync.when(
      data: (rows) {
        if (rows.isEmpty) {
          return Center(
            child: Text(
              'No warehouse stock data yet.',
              style: TextStyle(color: AppTheme.mutedTextColor(context)),
            ),
          );
        }

        final list = topOnly ? rows.take(5).toList() : rows;
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final row = list[index];
            final name = row['warehouse_name']?.toString() ?? 'Warehouse';
            final location = row['location']?.toString() ?? '';
            final qty = row['total_quantity'] ?? 0;
            final products = row['product_count'] ?? 0;
            final colors = row['color_count'] ?? 0;

            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                final wid = row['warehouse_id']?.toString() ?? '';
                if (wid.isEmpty) return;
                context.go(
                  '/products?warehouseId=${Uri.encodeQueryComponent(wid)}&warehouseName=${Uri.encodeQueryComponent(name)}',
                );
              },
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.inputFillColor(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            location.isNotEmpty ? '$name • $location' : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primaryTextColor(context),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Products: $products • Colors: $colors',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.secondaryTextColor(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Qty: $qty',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.success,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(
        child: SkeletonLoading(width: double.infinity, height: 180),
      ),
      error: (_, __) => Center(
        child: Text(
          'Unable to load warehouse stock.',
          style: TextStyle(color: AppTheme.mutedTextColor(context)),
        ),
      ),
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
            Text('Folders',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            TextButton(
              onPressed: () => context.go('/products'),
              child: Text('See All',
                  style: TextStyle(color: AppTheme.primary, fontSize: 13)),
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
                separatorBuilder: (_, __) => const SizedBox(width: 10),
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
          loading: () =>
              const SkeletonLoading(width: double.infinity, height: 112),
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
            Text('Recent Activity',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            TextButton(
              onPressed: () => context.go('/stock-activity'),
              child: Text('View All',
                  style: TextStyle(color: AppTheme.primary, fontSize: 13)),
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
                  color: AppTheme.surfaceColor(context),
                  borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text('No transactions yet',
                    style: TextStyle(color: AppTheme.mutedTextColor(context))),
              );
            }
            return Column(
              children: txns
                  .take(5)
                  .map<Widget>((txn) => _ActivityRow(txn: txn))
                  .toList(),
            );
          },
          loading: () => const SkeletonList(count: 3, height: 64),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  void _showNotificationsBottomSheet(BuildContext context, AppUser? user) {
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
                  data: (p) => p
                      .where((x) => x.stockStatus == StockStatus.lowStock)
                      .toList(),
                  orElse: () => [],
                );

                final recentTxs = transactionsAsync.maybeWhen(
                  data: (txs) => txs.take(15).toList(),
                  orElse: () => [],
                );

                return Container(
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundColor(context),
                    borderRadius: const BorderRadius.only(
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
                            Text(
                              'Notifications & Alerts',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.primaryTextColor(context),
                              ),
                            ),
                            if (lowStockProds.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.danger.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${lowStockProds.length} Alerts',
                                  style: TextStyle(
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
                          length: user?.canViewStockActivity == true ? 2 : 1,
                          child: Column(
                            children: [
                              if (user?.canViewStockActivity == true)
                                TabBar(
                                  indicatorColor: AppTheme.primary,
                                  labelColor: AppTheme.primary,
                                  unselectedLabelColor: AppTheme.textSecondary,
                                  labelStyle: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13),
                                  tabs: const [
                                    Tab(text: '🚨 Critical Alerts'),
                                    Tab(text: '📝 Activity Log'),
                                  ],
                                ),
                              Expanded(
                                child: TabBarView(
                                  children: [
                                    // 1. Alerts View
                                    _buildAlertsTab(
                                        lowStockProds, scrollController),
                                    // 2. Activity Log View
                                    if (user?.canViewStockActivity == true)
                                      _buildActivityTab(
                                          recentTxs, scrollController),
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

  Widget _buildAlertsTab(
      List<dynamic> lowStockProds, ScrollController scrollController) {
    if (lowStockProds.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline_rounded,
                color: AppTheme.success, size: 48),
            const SizedBox(height: 12),
            Text(
              'All Systems Healthy',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryTextColor(context)),
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
                    child: Icon(Icons.warning_rounded,
                        color: AppTheme.danger, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.code,
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: AppTheme.primaryTextColor(context)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          product.name,
                          style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.secondaryTextColor(context)),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              'Stock: ${AppFormatters.formatQuantity(product.quantity, product.pcsPerCarton)}',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.danger),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Threshold: ${product.threshold}',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded,
                      size: 12, color: AppTheme.mutedTextColor(context)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActivityTab(
      List<dynamic> recentTxs, ScrollController scrollController) {
    if (recentTxs.isEmpty) {
      return Center(
        child: Text('No recent transaction activity.',
            style: TextStyle(color: AppTheme.secondaryTextColor(context))),
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
                      color: (isStockIn ? AppTheme.success : AppTheme.danger)
                          .withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isStockIn
                          ? Icons.south_west_rounded
                          : Icons.north_east_rounded,
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
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: AppTheme.primaryTextColor(context)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${isStockIn ? "Stocked In" : "Stocked Out"}: ${AppFormatters.formatQuantity(tx.quantity, tx.pcsPerCarton)}',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryTextColor(context)),
                        ),
                        if (tx.workerName != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'By: ${tx.workerName}',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.secondaryTextColor(context)),
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
                        style: TextStyle(
                            fontSize: 10,
                            color: AppTheme.mutedTextColor(context)),
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
                borderRadius: BorderRadius.circular(AppTheme.radiusMD),
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
          color: AppTheme.surfaceColor(context),
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
      data: (products) => products.where((p) => p.category == category).length,
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
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_rounded, color: AppTheme.primary, size: 22),
            const SizedBox(height: 6),
            Text(
              category,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: AppTheme.primaryTextColor(context),
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$count items',
              style: TextStyle(
                  fontSize: 10, color: AppTheme.secondaryTextColor(context)),
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
        color: AppTheme.surfaceColor(context),
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
              borderRadius: BorderRadius.circular(AppTheme.radiusMD),
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
                  txn.productName?.toString().isEmpty == true
                      ? 'Unknown'
                      : txn.productName.toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  txn.workerName?.toString() ?? '',
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
            '${isIn ? '+' : '-'}${AppFormatters.formatQuantity(txn.quantity as int, txn.pcsPerCarton as int?)}',
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
