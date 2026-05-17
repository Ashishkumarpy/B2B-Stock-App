import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/transaction.dart';
import '../../providers/transactions_provider.dart';
import '../../widgets/skeleton_loading.dart';

class StockActivityScreen extends ConsumerWidget {
  const StockActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txnsAsync = ref.watch(transactionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Stock Activity')),
      body: txnsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppTheme.sp16),
          child: SkeletonList(count: 8, height: 72),
        ),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppTheme.danger),
              const SizedBox(height: AppTheme.sp16),
              Text('Error: $error'),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () =>
                    ref.read(transactionsProvider.notifier).fetchTransactions(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (txns) {
          if (txns.isEmpty) {
            return const Center(child: Text('No transactions found.'));
          }
          return RefreshIndicator(
            onRefresh: () =>
                ref.read(transactionsProvider.notifier).fetchTransactions(),
            child: ListView.builder(
              padding: const EdgeInsets.all(AppTheme.sp16),
              itemCount: txns.length,
              itemBuilder: (context, index) {
                return _StockActivityTile(txn: txns[index]);
              },
            ),
          );
        },
      ),
    );
  }
}

class _StockActivityTile extends ConsumerWidget {
  const _StockActivityTile({required this.txn});

  final Transaction txn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // We can't use productByIdProvider here if it's not defined,
    // but txn already has productName and workerName.
    final isIn = txn.isStockIn;
    final actionColor = isIn ? AppTheme.success : AppTheme.danger;
    final iconBg = isIn ? AppTheme.successLight : AppTheme.dangerLight;

    final productName =
        txn.productName.isEmpty ? 'Unknown Product' : txn.productName;
    final workerName =
        txn.workerName.isEmpty ? 'Unknown Worker' : txn.workerName;
    final warehouseName = txn.warehouseName ?? 'Main Warehouse';

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.sp8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: ListTile(
        onTap: () => context.push('/products/${txn.productId}'),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(AppTheme.radiusSM),
          ),
          child: Icon(
            isIn ? Icons.south_west_rounded : Icons.north_east_rounded,
            color: actionColor,
            size: 18,
          ),
        ),
        title: Text(
          productName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '$workerName • $warehouseName • ${DateFormat('dd MMM, hh:mm a').format(txn.createdAt)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11),
        ),
        trailing: Text(
          '${isIn ? '+' : '-'}${txn.quantity}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: actionColor,
                fontWeight: FontWeight.w900,
              ),
        ),
      ),
    );
  }
}
