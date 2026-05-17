import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'products_provider.dart';
import 'transactions_provider.dart';
import '../../domain/usecases/ai/stock_ai_engine.dart';

final aiInsightsProvider = Provider<AsyncValue<List<String>>>((ref) {
  final productsAsync = ref.watch(productsProvider);
  final transactionsAsync = ref.watch(transactionsProvider);

  return productsAsync.when(
    data: (products) => transactionsAsync.when(
      data: (transactions) {
        final insights = StockAiEngine.generateInsights(products, transactions);
        return AsyncValue.data(insights);
      },
      loading: () => const AsyncValue.loading(),
      error: (err, stack) => AsyncValue.error(err, stack),
    ),
    loading: () => const AsyncValue.loading(),
    error: (err, stack) => AsyncValue.error(err, stack),
  );
});
