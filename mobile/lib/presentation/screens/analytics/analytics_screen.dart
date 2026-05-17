import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/products_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../../domain/entities/product.dart';
import '../../../domain/entities/transaction.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  DateTime? _selectedDate;
  int? _selectedYear;

  String _formatDate(DateTime d) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.day.toString().padLeft(2, '0')}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);
    final transactionsAsync = ref.watch(transactionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Real-Time Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.read(productsProvider.notifier).fetchProducts();
              ref.read(transactionsProvider.notifier).fetchTransactions();
            },
          ),
        ],
      ),
      body: productsAsync.when(
        data: (products) => transactionsAsync.when(
          data: (transactions) => SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(AppTheme.sp16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRealtimePulseHeader(),
                const SizedBox(height: AppTheme.sp16),
                _buildFilterBar(transactions),
                const SizedBox(height: AppTheme.sp16),
                _buildOverviewCards(products),
                const SizedBox(height: AppTheme.sp24),
                _buildMonthlyTransactionFlow(transactions),
                const SizedBox(height: AppTheme.sp24),
                _buildCategoryDistribution(products),
                const SizedBox(height: AppTheme.sp24),
                _buildSectionTitle('Inventory Health'),
                const SizedBox(height: AppTheme.sp12),
                _buildHealthStats(products),
              ],
            ),
          ),
          loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
          error: (err, _) => Center(child: Text('Transactions Error: $err')),
        ),
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
        error: (err, _) => Center(child: Text('Products Error: $err')),
      ),
    );
  }

  Widget _buildRealtimePulseHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.1)),
      ),
      child: const Row(
        children: [
          _PulseIndicator(),
          SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Supabase Live Feed Active',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppTheme.primary,
                ),
              ),
              Text(
                'Streaming realtime changes instantly',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(List<Transaction> transactions) {
    // Scan transactions for all unique years
    final availableYears = transactions.map((t) => t.createdAt.year).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    if (availableYears.isEmpty) {
      availableYears.add(DateTime.now().year);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Interactive Filters',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Date picker button
              Expanded(
                child: OutlinedButton.icon(
                  icon: Icon(
                    Icons.calendar_today_rounded,
                    size: 14,
                    color: _selectedDate != null ? AppTheme.primary : AppTheme.textSecondary,
                  ),
                  label: Text(
                    _selectedDate != null ? _formatDate(_selectedDate!) : 'Select Date',
                    style: TextStyle(
                      color: _selectedDate != null ? AppTheme.primary : AppTheme.textSecondary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    side: BorderSide(
                      color: _selectedDate != null ? AppTheme.primary : Colors.grey.withValues(alpha: 0.2),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                    ),
                  ),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setState(() {
                        _selectedDate = picked;
                      });
                    }
                  },
                ),
              ),
              if (_selectedDate != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppTheme.danger, size: 20),
                  onPressed: () => setState(() => _selectedDate = null),
                ),
              ],
              const SizedBox(width: 8),
              // Year selection dropdown
              Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                  border: Border.all(
                    color: _selectedYear != null ? AppTheme.primary : Colors.grey.withValues(alpha: 0.2),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int?>(
                    value: _selectedYear,
                    hint: const Text('Year', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                    icon: const Icon(Icons.arrow_drop_down_rounded, color: AppTheme.textSecondary),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('All Years', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                      ),
                      ...availableYears.map((y) => DropdownMenuItem<int?>(
                        value: y,
                        child: Text('$y', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                      )),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _selectedYear = val;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.2),
    );
  }

  Widget _buildOverviewCards(List<Product> products) {
    final totalItems = products.length;
    final totalStock = products.fold<int>(0, (sum, p) => sum + p.quantity);
    final lowStock = products.where((p) => p.stockStatus == StockStatus.lowStock).length;

    return Row(
      children: [
        _StatCard(
          label: 'Total Products',
          value: '$totalItems',
          color: AppTheme.primary,
        ),
        const SizedBox(width: AppTheme.sp12),
        _StatCard(
          label: 'Total Units',
          value: '$totalStock',
          color: AppTheme.success,
        ),
        const SizedBox(width: AppTheme.sp12),
        _StatCard(
          label: 'Alerts',
          value: '$lowStock',
          color: AppTheme.danger,
        ),
      ],
    );
  }

  Widget _buildMonthlyTransactionFlow(List<Transaction> transactions) {
    final today = DateTime.now();
    final monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    
    // 1. Calculate Today's / Selected Date's Stats
    final filterDate = _selectedDate ?? today;
    int stockInSum = 0;
    int stockOutSum = 0;
    
    for (final t in transactions) {
      final tDate = t.createdAt;
      if (tDate.year == filterDate.year &&
          tDate.month == filterDate.month &&
          tDate.day == filterDate.day) {
        if (t.isStockIn) {
          stockInSum += t.quantity;
        } else {
          stockOutSum += t.quantity;
        }
      }
    }

    // 2. Generate monthly trend data respecting year filter
    final targetYear = _selectedYear ?? today.year;
    final List<_MonthTrendData> monthlyTrend;

    if (_selectedYear == null || _selectedYear == today.year) {
      // Last 6 months ending in the current month
      monthlyTrend = List.generate(6, (i) {
        final d = DateTime(today.year, today.month - (5 - i), 1);
        return _MonthTrendData(
          label: monthNames[d.month - 1],
          monthIdx: d.month,
          year: d.year,
          stockIn: 0,
          stockOut: 0,
        );
      });
    } else {
      // 6 key months of the selected year (July to December)
      monthlyTrend = List.generate(6, (i) {
        final d = DateTime(targetYear, 7 + i, 1);
        return _MonthTrendData(
          label: monthNames[d.month - 1],
          monthIdx: d.month,
          year: d.year,
          stockIn: 0,
          stockOut: 0,
        );
      });
    }

    for (final t in transactions) {
      final tDate = t.createdAt;
      for (final trend in monthlyTrend) {
        if (trend.monthIdx == tDate.month && trend.year == tDate.year) {
          if (t.isStockIn) {
            trend.stockIn += t.quantity;
          } else {
            trend.stockOut += t.quantity;
          }
        }
      }
    }

    final double maxVal = monthlyTrend
        .map((m) => m.stockIn > m.stockOut ? m.stockIn.toDouble() : m.stockOut.toDouble())
        .reduce((a, b) => a > b ? a : b);
    final double computedMax = maxVal == 0 ? 100.0 : maxVal * 1.15;

    final dateLabel = _selectedDate != null ? _formatDate(_selectedDate!) : 'Today';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Monthly Stock Flow'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(AppTheme.radiusXL),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 180,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: computedMax,
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipColor: (_) => Colors.black.withValues(alpha: 0.8),
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          return BarTooltipItem(
                            '${rodIndex == 0 ? "IN: " : "OUT: "}${rod.toY.toInt()}',
                            const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                          );
                        },
                      ),
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final idx = value.toInt();
                            if (idx >= 0 && idx < monthlyTrend.length) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  monthlyTrend[idx].label,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    barGroups: monthlyTrend.asMap().entries.map((e) {
                      return BarChartGroupData(
                        x: e.key,
                        barRods: [
                          BarChartRodData(
                            toY: e.value.stockIn.toDouble(),
                            color: AppTheme.primary,
                            width: 10,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(4),
                              topRight: Radius.circular(4),
                            ),
                          ),
                          BarChartRodData(
                            toY: e.value.stockOut.toDouble(),
                            color: AppTheme.primary.withValues(alpha: 0.4),
                            width: 10,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(4),
                              topRight: Radius.circular(4),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Icon(Icons.circle, color: AppTheme.primary, size: 10),
                      SizedBox(width: 6),
                      Text('Stock In', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
                    ],
                  ),
                  SizedBox(width: 24),
                  Row(
                    children: [
                      Icon(Icons.circle, color: AppTheme.primaryLight, size: 10),
                      SizedBox(width: 6),
                      Text('Stock Out', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.sp16),
        Row(
          children: [
            _TransactionSummaryCard(
              label: 'Stock In ($dateLabel)',
              value: '$stockInSum',
              icon: Icons.trending_up_rounded,
              color: AppTheme.primary,
              onTap: () => context.push('/stock-activity'),
            ),
            const SizedBox(width: AppTheme.sp12),
            _TransactionSummaryCard(
              label: 'Stock Out ($dateLabel)',
              value: '$stockOutSum',
              icon: Icons.trending_down_rounded,
              color: AppTheme.danger,
              onTap: () => context.push('/stock-activity'),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.sp12),
        _NetFlowCard(
          label: 'Net Flow ($dateLabel)',
          value: '${stockInSum - stockOutSum >= 0 ? "+" : ""}${stockInSum - stockOutSum}',
          color: (stockInSum - stockOutSum) >= 0 ? AppTheme.success : AppTheme.danger,
          onTap: () => context.push('/stock-activity'),
        ),
      ],
    );
  }

  Widget _buildCategoryDistribution(List<Product> products) {
    final categories = <String, int>{};
    for (var p in products) {
      final cat = p.category.isNotEmpty ? p.category : 'Uncategorized';
      categories[cat] = (categories[cat] ?? 0) + 1;
    }

    final sorted = categories.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(5).toList();

    final colors = [
      AppTheme.primary,
      AppTheme.success,
      AppTheme.warning,
      AppTheme.danger,
      Colors.blue,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Category Distribution'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(AppTheme.sp16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(AppTheme.radiusXL),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 160,
                child: PieChart(
                  PieChartData(
                    sections: top.asMap().entries.map((e) {
                      return PieChartSectionData(
                        value: e.value.value.toDouble(),
                        title: '${e.value.value}',
                        color: colors[e.key % colors.length],
                        radius: 40,
                        titleStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      );
                    }).toList(),
                    centerSpaceRadius: 35,
                    sectionsSpace: 2,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: top.asMap().entries.map((e) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, color: colors[e.key % colors.length], size: 8),
                      const SizedBox(width: 4),
                      Text(
                        e.value.key,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHealthStats(List<Product> products) {
    final lowStock = products.where((p) => p.stockStatus == StockStatus.lowStock).length;
    final outOfStock = products.where((p) => p.stockStatus == StockStatus.outOfStock).length;
    final healthy = products.length - lowStock - outOfStock;

    return Column(
      children: [
        _HealthRow(
          label: 'Healthy Stock',
          count: healthy,
          color: AppTheme.success,
          total: products.length,
        ),
        const SizedBox(height: 12),
        _HealthRow(
          label: 'Low Stock Alerts',
          count: lowStock,
          color: AppTheme.warning,
          total: products.length,
        ),
        const SizedBox(height: 12),
        _HealthRow(
          label: 'Out of Stock',
          count: outOfStock,
          color: AppTheme.danger,
          total: products.length,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppTheme.sp12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppTheme.radiusLG),
          border: Border.all(color: color.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
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

  const _HealthRow({
    required this.label,
    required this.count,
    required this.color,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final percent = total > 0 ? count / total : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text(
              '$count',
              style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: percent,
          backgroundColor: color.withValues(alpha: 0.1),
          valueColor: AlwaysStoppedAnimation<Color>(color),
          borderRadius: BorderRadius.circular(4),
          minHeight: 8,
        ),
      ],
    );
  }
}

class _PulseIndicator extends StatefulWidget {
  const _PulseIndicator();

  @override
  State<_PulseIndicator> createState() => _PulseIndicatorState();
}

class _PulseIndicatorState extends State<_PulseIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.8, end: 1.2).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Colors.green,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.greenAccent,
              blurRadius: 6,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthTrendData {
  final String label;
  final int monthIdx;
  final int year;
  int stockIn;
  int stockOut;

  _MonthTrendData({
    required this.label,
    required this.monthIdx,
    required this.year,
    required this.stockIn,
    required this.stockOut,
  });
}

class _TransactionSummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _TransactionSummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusXL),
          child: Container(
            padding: const EdgeInsets.all(AppTheme.sp16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(AppTheme.radiusXL),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  value,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NetFlowCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  const _NetFlowCard({
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppTheme.sp16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AppTheme.radiusXL),
            border: Border.all(color: color.withValues(alpha: 0.15)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Calculated flow metric',
                    style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
                  ),
                ],
              ),
              Text(
                value,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
