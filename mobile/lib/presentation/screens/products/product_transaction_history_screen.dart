import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/product.dart';
import '../../providers/products_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../widgets/connection_warning.dart';
import '../../widgets/transaction_activity_card.dart';

class ProductTransactionHistoryScreen extends ConsumerWidget {
  final String productId;

  const ProductTransactionHistoryScreen({
    super.key,
    required this.productId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = ref.watch(productsProvider).maybeWhen(
          data: (products) => _findProduct(products, productId),
          orElse: () => null,
        );
    final txsAsync = ref.watch(productTransactionsProvider(productId));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Product History'),
            if (product != null)
              Text(
                product.code.isNotEmpty ? product.code : product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppTheme.secondaryTextColor(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh history',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.invalidate(productTransactionsProvider(productId));
            },
          ),
        ],
      ),
      body: txsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ConnectionWarning(
          error: error,
          onRetry: () => ref.invalidate(productTransactionsProvider(productId)),
        ),
        data: (transactions) {
          if (transactions.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 48,
                      color: AppTheme.mutedTextColor(context)
                          .withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No movements recorded yet',
                      style: TextStyle(
                        color: AppTheme.secondaryTextColor(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              await ref
                  .refresh(productTransactionsProvider(productId).future)
                  .then<void>((_) {});
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppTheme.sp16),
              itemCount: transactions.length,
              itemBuilder: (context, index) {
                return TransactionActivityCard(
                  transaction: transactions[index],
                  margin: const EdgeInsets.only(bottom: AppTheme.sp8),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Product? _findProduct(List<Product> products, String id) {
    for (final product in products) {
      if (product.id == id) return product;
    }
    return null;
  }
}
