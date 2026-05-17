import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/products_provider.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
      ),
      body: productsAsync.when(
        data: (products) => SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.sp24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildOverviewCards(products),
              const SizedBox(height: AppTheme.sp32),
              _buildStockDistribution(products),
              const SizedBox(height: AppTheme.sp32),
              _buildSectionTitle('Inventory Health'),
              const SizedBox(height: AppTheme.sp16),
              _buildHealthStats(products),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildOverviewCards(List<dynamic> products) {
    final totalItems = products.length;
    final totalStock =
        products.fold<int>(0, (sum, p) => sum + p.quantity as int);
    final lowStock =
        products.where((p) => p.stockStatus == StockStatus.lowStock).length;

    return Row(
      children: [
        _StatCard(
            label: 'Total SKU', value: '$totalItems', color: AppTheme.primary),
        const SizedBox(width: AppTheme.sp16),
        _StatCard(
            label: 'Total Units',
            value: '$totalStock',
            color: AppTheme.success),
        const SizedBox(width: AppTheme.sp16),
        _StatCard(label: 'Alerts', value: '$lowStock', color: AppTheme.danger),
      ],
    );
  }

  Widget _buildStockDistribution(List<dynamic> products) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Category Distribution'),
        const SizedBox(height: AppTheme.sp24),
        SizedBox(
          height: 200,
          child: PieChart(
            PieChartData(
              sections: _buildPieSections(products),
              centerSpaceRadius: 40,
              sectionsSpace: 2,
            ),
          ),
        ),
      ],
    );
  }

  List<PieChartSectionData> _buildPieSections(List<dynamic> products) {
    final categories = <String, int>{};
    for (var p in products) {
      categories[p.category] = (categories[p.category] ?? 0) + 1;
    }

    final sorted = categories.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(5).toList();

    return top.asMap().entries.map((e) {
      final colors = [
        AppTheme.primary,
        AppTheme.success,
        AppTheme.warning,
        AppTheme.danger,
        Colors.blue
      ];
      return PieChartSectionData(
        value: e.value.value.toDouble(),
        title: e.value.key,
        color: colors[e.key % colors.length],
        radius: 50,
        titleStyle: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
      );
    }).toList();
  }

  Widget _buildHealthStats(List<dynamic> products) {
    final lowStock =
        products.where((p) => p.stockStatus == StockStatus.lowStock).length;
    final outOfStock =
        products.where((p) => p.stockStatus == StockStatus.outOfStock).length;
    final healthy = products.length - lowStock - outOfStock;

    return Column(
      children: [
        _HealthRow(
            label: 'Healthy Stock',
            count: healthy,
            color: AppTheme.success,
            total: products.length),
        const SizedBox(height: 12),
        _HealthRow(
            label: 'Low Stock Alerts',
            count: lowStock,
            color: AppTheme.warning,
            total: products.length),
        const SizedBox(height: 12),
        _HealthRow(
            label: 'Out of Stock',
            count: outOfStock,
            color: AppTheme.danger,
            total: products.length),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatCard(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppTheme.sp16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(AppTheme.radiusMD),
          border: Border.all(color: color.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 20, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }
}

class _HealthRow extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final int total;

  const _HealthRow(
      {required this.label,
      required this.count,
      required this.color,
      required this.total});

  @override
  Widget build(BuildContext context) {
    final percent = total > 0 ? count / total : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
            Text('$count',
                style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: percent,
          backgroundColor: color.withOpacity(0.1),
          valueColor: AlwaysStoppedAnimation<Color>(color),
          borderRadius: BorderRadius.circular(4),
          minHeight: 8,
        ),
      ],
    );
  }
}
