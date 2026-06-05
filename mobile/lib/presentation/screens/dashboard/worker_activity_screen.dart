import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/transaction.dart';
import '../../providers/transactions_provider.dart';
import '../../widgets/connection_warning.dart';
import '../../widgets/skeleton_loading.dart';
import '../../../core/utils/formatters.dart';

class WorkerActivityScreen extends ConsumerWidget {
  const WorkerActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(transactionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recent Activity'),
      ),
      body: transactionsAsync.when(
        data: (transactions) {
          if (transactions.isEmpty) {
            return const Center(child: Text('No recent activity'));
          }

          return RefreshIndicator(
            onRefresh: () =>
                ref.read(transactionsProvider.notifier).fetchTransactions(),
            child: ListView.separated(
              padding: const EdgeInsets.all(AppTheme.sp16),
              itemCount: transactions.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final tx = transactions[index];
                return _ActivityTile(transaction: tx);
              },
            ),
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.all(AppTheme.sp16),
          child: SkeletonList(count: 8, height: 72),
        ),
        error: (err, _) => ConnectionWarning(
          error: err,
          onRetry: () =>
              ref.read(transactionsProvider.notifier).fetchTransactions(),
        ),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final Transaction transaction;

  const _ActivityTile({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isStockIn = transaction.type == TransactionType.stockIn;
    final color = isStockIn ? AppTheme.success : AppTheme.danger;
    final dateStr = DateFormat('MMM d, h:mm a').format(transaction.createdAt);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.sp12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppTheme.sp8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isStockIn
                  ? Icons.add_circle_outline
                  : Icons.remove_circle_outline,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: AppTheme.sp16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.productName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${transaction.workerName} • ${transaction.warehouseName ?? 'Main'}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isStockIn ? '+' : '-'}${AppFormatters.formatQuantity(transaction.quantity, transaction.pcsPerCarton)}',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              Text(
                dateStr,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
