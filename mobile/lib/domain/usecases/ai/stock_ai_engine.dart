import '../../entities/product.dart';
import '../../entities/transaction.dart';
import '../../../core/constants/app_constants.dart';

class StockAiEngine {
  /// Core logic for AI-driven stock analysis and demand prediction.
  /// Easily replaceable with a real ML model (TFLite, Cloud ML, etc.)

  static List<String> generateInsights(
      List<Product> products, List<Transaction> transactions) {
    final insights = <String>[];

    // 1. Critical Stock Alerts
    final outOfStock = products.where((p) => p.quantity <= 0).toList();
    if (outOfStock.isNotEmpty) {
      insights.add(
          '⚠️ ${outOfStock.length} items are currently out of stock. Immediate restock required.');
    }

    // 2. Low Stock Predictions
    final lowStock = products
        .where((p) => p.quantity > 0 && p.quantity <= p.threshold)
        .toList();
    if (lowStock.isNotEmpty) {
      insights.add(
          '📉 ${lowStock.length} items have reached their threshold. Stock may run out within 3 days.');
    }

    // 3. Demand Trends
    if (transactions.isNotEmpty) {
      final now = DateTime.now();
      final last7Days = transactions
          .where(
              (t) => t.createdAt.isAfter(now.subtract(const Duration(days: 7))))
          .toList();

      if (last7Days.isNotEmpty) {
        final stockOutCount =
            last7Days.where((t) => t.type == TransactionType.stockOut).length;
        final stockInCount =
            last7Days.where((t) => t.type == TransactionType.stockIn).length;

        if (stockOutCount > stockInCount * 1.5) {
          insights.add(
              '🔥 High demand alert: Outbound volume is 50% higher than inbound this week.');
        } else if (stockInCount > stockOutCount * 2) {
          insights.add(
              '📦 Inventory surge: Significant stock inflow detected. Ensure storage capacity is optimized.');
        }
      }
    }

    // 4. Optimization Tips
    if (products.length > 50) {
      insights.add(
          '💡 Tip: Your inventory has grown 20% this month. Consider categorizing by turnover rate (ABC analysis).');
    }

    if (insights.isEmpty) {
      insights.add(
          '✅ Inventory is stable. No critical anomalies detected by AI engine.');
    }

    return insights;
  }

  static double predictDemand(Product product, List<Transaction> transactions) {
    // Simple linear regression or weighted average mock
    final productTransactions = transactions
        .where((t) =>
            t.productId == product.id && t.type == TransactionType.stockOut)
        .toList();

    if (productTransactions.isEmpty) return 0.0;

    final totalOut =
        productTransactions.fold<int>(0, (sum, t) => sum + t.quantity);
    final avgDailyDemand = totalOut / 30; // Assuming 30 days history

    return avgDailyDemand * 7; // Predict next 7 days
  }
}
