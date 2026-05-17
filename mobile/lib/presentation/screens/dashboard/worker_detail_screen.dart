import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/transaction.dart';
import '../../providers/transactions_provider.dart';
import '../../providers/workers_provider.dart';
import '../../widgets/skeleton_loading.dart';

class WorkerDetailScreen extends ConsumerWidget {
  final String userId;

  const WorkerDetailScreen({
    super.key,
    required this.userId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workersAsync = ref.watch(workersProvider);
    final transactionsAsync = ref.watch(transactionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Worker Details')),
      body: workersAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppTheme.sp16),
          child: SkeletonList(count: 4, height: 96),
        ),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (workers) {
          final worker =
              workers.where((w) => '${w['id']}' == userId).firstOrNull;
          final name = worker?['name']?.toString() ?? 'Worker';
          final phone = worker?['phone']?.toString();

          final transactions = transactionsAsync.maybeWhen(
            data: (items) => items
                .where((t) => t.workerId == userId || t.userId == userId)
                .toList(),
            orElse: () => <Transaction>[],
          );
          final stockIn = transactions
              .where((t) => t.type == TransactionType.stockIn)
              .fold<int>(0, (sum, t) => sum + t.quantity);
          final stockOut = transactions
              .where((t) => t.type == TransactionType.stockOut)
              .fold<int>(0, (sum, t) => sum + t.quantity);

          return RefreshIndicator(
            onRefresh: () =>
                ref.read(transactionsProvider.notifier).fetchTransactions(),
            child: ListView(
              padding: const EdgeInsets.all(AppTheme.sp16),
              children: [
                _WorkerHeader(name: name, phone: phone),
                const SizedBox(height: AppTheme.sp16),
                Row(
                  children: [
                    Expanded(
                      child: _MetricCard(
                        label: 'Stock In',
                        value: stockIn.toString(),
                        color: AppTheme.success,
                        icon: Icons.south_west_rounded,
                      ),
                    ),
                    const SizedBox(width: AppTheme.sp12),
                    Expanded(
                      child: _MetricCard(
                        label: 'Stock Out',
                        value: stockOut.toString(),
                        color: AppTheme.danger,
                        icon: Icons.north_east_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.sp24),
                const Text(
                  'Recent Activity',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: AppTheme.sp8),
                if (transactions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppTheme.sp32),
                    child: Center(
                        child: Text('No activity recorded for this worker.')),
                  )
                else
                  ...transactions.map((transaction) =>
                      _WorkerTransactionTile(transaction: transaction)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _WorkerHeader extends StatelessWidget {
  final String name;
  final String? phone;

  const _WorkerHeader({
    required this.name,
    required this.phone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.sp20),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white,
            child: Text(
              name.isEmpty ? '?' : name[0].toUpperCase(),
              style: const TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.w900,
                fontSize: 24,
              ),
            ),
          ),
          const SizedBox(width: AppTheme.sp16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (phone != null && phone!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    phone!,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.sp16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        border: Border.all(color: color.withOpacity(0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: AppTheme.sp12),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _WorkerTransactionTile extends StatelessWidget {
  final Transaction transaction;

  const _WorkerTransactionTile({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isIn = transaction.type == TransactionType.stockIn;
    final color = isIn ? AppTheme.success : AppTheme.danger;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(AppTheme.sp8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isIn ? Icons.south_west_rounded : Icons.north_east_rounded,
          color: color,
          size: 18,
        ),
      ),
      title: Text(
        transaction.productName.isEmpty
            ? 'Unknown Product'
            : transaction.productName,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(DateFormat('MMM d, h:mm a').format(transaction.createdAt)),
      trailing: Text(
        '${isIn ? '+' : '-'}${transaction.quantity}',
        style: TextStyle(color: color, fontWeight: FontWeight.w900),
      ),
    );
  }
}
