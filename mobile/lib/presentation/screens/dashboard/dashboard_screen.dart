import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/version_check_service.dart';
import '../../providers/products_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../providers/ai_insights_provider.dart';
import '../../providers/categories_provider.dart';
import '../../providers/auth_provider.dart';
import '../../../domain/entities/product.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/ai_insight_card.dart';
import '../../widgets/stock_chart_widget.dart';
import '../../widgets/skeleton_loading.dart';
import '../../widgets/product_card.dart';

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
    final insightsAsync = ref.watch(aiInsightsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final user = ref.watch(authStateProvider).user;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(productsProvider);
          ref.invalidate(transactionsProvider);
          ref.invalidate(aiInsightsProvider);
          ref.invalidate(categoriesProvider);
        },
        child: CustomScrollView(
          slivers: [
            _buildAppBar(user?.name ?? 'Main Warehouse'),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.sp16, vertical: AppTheme.sp8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(user?.name ?? 'Admin'),
                    const SizedBox(height: AppTheme.sp16),
                    _buildStatsGrid(productsAsync),
                    const SizedBox(height: AppTheme.sp20),
                    _buildStockMovementSection(transactionsAsync),
                    const SizedBox(height: AppTheme.sp20),
                    _buildAiInsightsSection(insightsAsync),
                    const SizedBox(height: AppTheme.sp20),
                    _buildCategoriesSection(categoriesAsync),
                    const SizedBox(height: AppTheme.sp20),
                    _buildRecentProductsSection(productsAsync),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(String title) {
    return SliverAppBar(
      expandedHeight: 120,
      floating: true,
      pinned: true,
      elevation: 0,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding:
            const EdgeInsets.symmetric(horizontal: AppTheme.sp24, vertical: 16),
        centerTitle: false,
        title: Text(
          title,
          style: TextStyle(
            color: AppTheme.isDarkMode(context) ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_none_rounded),
          onPressed: () {},
        ),
        const SizedBox(width: AppTheme.sp16),
      ],
    );
  }

  Widget _buildHeader(String name) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome back,',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade500,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildStatsGrid(AsyncValue<List<dynamic>> productsAsync) {
    return productsAsync.when(
      data: (products) {
        final totalItems = products.length;
        final totalStock =
            products.fold<int>(0, (sum, p) => sum + (p.quantity as int));
        final lowStock =
            products.where((p) => p.quantity <= p.threshold).length;

        return AnimationLimiter(
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppTheme.sp16,
            crossAxisSpacing: AppTheme.sp16,
            childAspectRatio: 1.5,
            children: [
              _buildStatCard(
                  0,
                  'Total SKU',
                  '$totalItems',
                  Icons.inventory_2_rounded,
                  AppTheme.primary,
                  () => context.go('/products')),
              _buildStatCard(1, 'Total Units', '$totalStock',
                  Icons.layers_rounded, AppTheme.success, null),
              _buildStatCard(
                  2,
                  'Low Stock',
                  '$lowStock',
                  Icons.warning_amber_rounded,
                  AppTheme.warning,
                  () => context.go('/products?filter=low')),
              _buildStatCard(3, 'Analytics', 'View', Icons.analytics_rounded,
                  Colors.blue, () => context.go('/analytics')),
            ],
          ),
        );
      },
      loading: () => const SkeletonList(count: 2, height: 120),
      error: (err, _) => Center(child: Text('Error: $err')),
    );
  }

  Widget _buildStatCard(int pos, String title, String value, IconData icon,
      Color color, VoidCallback? onTap) {
    return AnimationConfiguration.staggeredGrid(
      position: pos,
      duration: const Duration(milliseconds: 375),
      columnCount: 2,
      child: ScaleAnimation(
        child: FadeInAnimation(
          child: StatCard(
            title: title,
            value: value,
            icon: icon,
            color: color,
            onTap: onTap,
          ),
        ),
      ),
    );
  }

  Widget _buildStockMovementSection(
      AsyncValue<List<dynamic>> transactionsAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Stock Movement',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () => context.go('/stock-activity'),
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.sp16),
        Container(
          height: 200,
          padding: const EdgeInsets.all(AppTheme.sp16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(AppTheme.radiusLG),
            border: Border.all(color: Colors.grey.withOpacity(0.1)),
          ),
          child: transactionsAsync.when(
            data: (transactions) =>
                StockChartWidget(transactions: transactions.cast()),
            loading: () =>
                const SkeletonLoading(width: double.infinity, height: 160),
            error: (err, _) => Center(child: Text('Error: $err')),
          ),
        ),
      ],
    );
  }

  Widget _buildAiInsightsSection(AsyncValue<List<String>> insightsAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Smart Insights',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppTheme.sp16),
        insightsAsync.when(
          data: (insights) => Column(
            children: insights
                .asMap()
                .entries
                .map((e) => AiInsightCard(insight: e.value, index: e.key))
                .toList(),
          ),
          loading: () => const SkeletonList(count: 2, height: 80),
          error: (err, _) => Center(child: Text('Error: $err')),
        ),
      ],
    );
  }

  Widget _buildCategoriesSection(AsyncValue<List<String>> categoriesAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Categories',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppTheme.sp16),
        categoriesAsync.when(
          data: (categories) => SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppTheme.sp12),
              itemBuilder: (context, index) =>
                  _CategoryCard(category: categories[index]),
            ),
          ),
          loading: () =>
              const SkeletonLoading(width: double.infinity, height: 120),
          error: (err, _) => Center(child: Text('Error: $err')),
        ),
      ],
    );
  }

  Widget _buildRecentProductsSection(AsyncValue<List<Product>> productsAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Inventory',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () => context.go('/products'),
              child: const Text('See All'),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.sp16),
        productsAsync.when(
          data: (products) => GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.82,
              crossAxisSpacing: AppTheme.sp12,
              mainAxisSpacing: AppTheme.sp12,
            ),
            itemCount: products.length > 4 ? 4 : products.length,
            itemBuilder: (context, index) => ProductCard(
              product: products[index],
              onTap: () => context.push('/products/${products[index].id}'),
            ),
          ),
          loading: () => const SkeletonList(count: 2, height: 200),
          error: (err, _) => Center(child: Text('Error: $err')),
        ),
      ],
    );
  }
}

class _CategoryCard extends ConsumerWidget {
  final String category;
  const _CategoryCard({required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(categorySummaryProvider(category));

    return summaryAsync.when(
      data: (summary) => InkWell(
        onTap: () =>
            context.push('/products?filter=${Uri.encodeComponent(category)}'),
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        child: Container(
          width: 140,
          padding: const EdgeInsets.all(AppTheme.sp12),
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.05),
            borderRadius: BorderRadius.circular(AppTheme.radiusLG),
            border: Border.all(color: AppTheme.primary.withOpacity(0.1)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(AppTheme.sp8),
                decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    shape: BoxShape.circle),
                child: const Icon(Icons.folder_rounded,
                    color: AppTheme.primary, size: 20),
              ),
              const Spacer(),
              Text(
                category,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                '${summary.productCount} Items',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
      loading: () => const SkeletonLoading(width: 140, height: 120),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
