import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/entities/transaction.dart';

class StockChartWidget extends StatelessWidget {
  final List<Transaction> transactions;

  const StockChartWidget({super.key, required this.transactions});

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return const Center(child: Text('No transaction history available.'));
    }

    // Process data for the last 7 days
    final now = DateTime.now();
    final dailyTotals = <int, double>{};
    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final dayKey = date.day;
      dailyTotals[dayKey] = 0;
    }

    for (var t in transactions) {
      final dayKey = t.createdAt.day;
      if (dailyTotals.containsKey(dayKey)) {
        if (t.type == TransactionType.stockIn) {
          dailyTotals[dayKey] = (dailyTotals[dayKey] ?? 0) + t.quantity;
        } else {
          dailyTotals[dayKey] = (dailyTotals[dayKey] ?? 0) - t.quantity;
        }
      }
    }

    final spots = dailyTotals.entries.toList().asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.value);
    }).toList();

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= dailyTotals.length) return const SizedBox.shrink();
                final day = dailyTotals.keys.elementAt(value.toInt());
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text('$day', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppTheme.primary,
            barWidth: 4,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: AppTheme.primary.withOpacity(0.1),
            ),
          ),
        ],
      ),
    );
  }
}
