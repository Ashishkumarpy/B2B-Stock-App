import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/transaction.dart';
import '../../providers/transactions_provider.dart';
import '../../widgets/skeleton_loading.dart';

enum ActivityFilter { today, all, stockIn, stockOut, customDate }

class StockActivityScreen extends ConsumerStatefulWidget {
  const StockActivityScreen({super.key});

  @override
  ConsumerState<StockActivityScreen> createState() => _StockActivityScreenState();
}

class _StockActivityScreenState extends ConsumerState<StockActivityScreen> {
  ActivityFilter _currentFilter = ActivityFilter.today;
  DateTime? _customFilterDate;

  String _formatDate(DateTime d) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.day.toString().padLeft(2, '0')}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final txnsAsync = ref.watch(transactionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Activity'),
        actions: [
          PopupMenuButton<ActivityFilter>(
            icon: const Icon(Icons.filter_list_rounded),
            tooltip: 'Filter Activities',
            onSelected: (ActivityFilter filter) async {
              if (filter == ActivityFilter.customDate) {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _customFilterDate ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) {
                  setState(() {
                    _currentFilter = ActivityFilter.customDate;
                    _customFilterDate = picked;
                  });
                }
              } else {
                setState(() {
                  _currentFilter = filter;
                  _customFilterDate = null;
                });
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<ActivityFilter>>[
              PopupMenuItem<ActivityFilter>(
                value: ActivityFilter.today,
                child: Row(
                  children: [
                    Icon(
                      Icons.today_rounded,
                      size: 18,
                      color: _currentFilter == ActivityFilter.today ? AppTheme.primary : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    const Text('Today', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              PopupMenuItem<ActivityFilter>(
                value: ActivityFilter.all,
                child: Row(
                  children: [
                    Icon(
                      Icons.all_inbox_rounded,
                      size: 18,
                      color: _currentFilter == ActivityFilter.all ? AppTheme.primary : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    const Text('All Activities', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<ActivityFilter>(
                value: ActivityFilter.stockIn,
                child: Row(
                  children: [
                    Icon(
                      Icons.south_west_rounded,
                      size: 18,
                      color: _currentFilter == ActivityFilter.stockIn ? AppTheme.primary : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    const Text('Stock In Only', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              PopupMenuItem<ActivityFilter>(
                value: ActivityFilter.stockOut,
                child: Row(
                  children: [
                    Icon(
                      Icons.north_east_rounded,
                      size: 18,
                      color: _currentFilter == ActivityFilter.stockOut ? AppTheme.primary : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    const Text('Stock Out Only', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<ActivityFilter>(
                value: ActivityFilter.customDate,
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 18,
                      color: _currentFilter == ActivityFilter.customDate ? AppTheme.primary : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _customFilterDate != null ? _formatDate(_customFilterDate!) : 'Choose Date...',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.read(transactionsProvider.notifier).fetchTransactions();
            },
          ),
        ],
      ),
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
                onPressed: () => ref.read(transactionsProvider.notifier).fetchTransactions(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (txns) {
          // Apply active filters
          List<Transaction> filteredTxns = txns;
          
          if (_currentFilter == ActivityFilter.today) {
            final now = DateTime.now();
            filteredTxns = txns.where((t) {
              return t.createdAt.year == now.year &&
                  t.createdAt.month == now.month &&
                  t.createdAt.day == now.day;
            }).toList();
          } else if (_currentFilter == ActivityFilter.stockIn) {
            filteredTxns = txns.where((t) => t.isStockIn).toList();
          } else if (_currentFilter == ActivityFilter.stockOut) {
            filteredTxns = txns.where((t) => t.isStockOut).toList();
          } else if (_currentFilter == ActivityFilter.customDate && _customFilterDate != null) {
            filteredTxns = txns.where((t) {
              return t.createdAt.year == _customFilterDate!.year &&
                  t.createdAt.month == _customFilterDate!.month &&
                  t.createdAt.day == _customFilterDate!.day;
            }).toList();
          }

          final String headerText;
          if (_currentFilter == ActivityFilter.today) {
            headerText = "Showing: Today's Activities";
          } else if (_currentFilter == ActivityFilter.all) {
            headerText = "Showing: All Activities";
          } else if (_currentFilter == ActivityFilter.stockIn) {
            headerText = "Showing: Stock In Only";
          } else if (_currentFilter == ActivityFilter.stockOut) {
            headerText = "Showing: Stock Out Only";
          } else if (_currentFilter == ActivityFilter.customDate && _customFilterDate != null) {
            headerText = "Showing: ${_formatDate(_customFilterDate!)}";
          } else {
            headerText = "Stock Activities";
          }

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: AppTheme.primary.withValues(alpha: 0.05),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.tune_rounded, size: 15, color: AppTheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          headerText,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                    if (_currentFilter != ActivityFilter.today)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _currentFilter = ActivityFilter.today;
                            _customFilterDate = null;
                          });
                        },
                        child: const Text(
                          'Reset to Today',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.danger,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: filteredTxns.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history_rounded, size: 48, color: Colors.grey.withValues(alpha: 0.4)),
                            const SizedBox(height: 12),
                            Text(
                              'No transactions matches the filter.',
                              style: TextStyle(color: Colors.grey[600], fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => ref.read(transactionsProvider.notifier).fetchTransactions(),
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(AppTheme.sp16),
                          itemCount: filteredTxns.length,
                          itemBuilder: (context, index) {
                            return _StockActivityTile(txn: filteredTxns[index]);
                          },
                        ),
                      ),
              ),
            ],
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
    final isIn = txn.isStockIn;
    final actionColor = isIn ? AppTheme.success : AppTheme.danger;
    final iconBg = isIn ? AppTheme.successLight : AppTheme.dangerLight;

    final productName = txn.productName.isEmpty ? 'Unknown Product' : txn.productName;
    final workerName = txn.workerName.isEmpty ? 'Unknown Worker' : txn.workerName;
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
          txn.productCode.isNotEmpty ? txn.productCode : 'No Code',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                productName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.person_rounded, size: 11, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(
                    workerName,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  ),
                  if (txn.colorName != null && txn.colorName!.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      '•  ${txn.colorName}',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Icon(Icons.storefront_rounded, size: 11, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      warehouseName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Icon(Icons.access_time_filled_rounded, size: 11, color: Colors.grey[400]),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('dd MMM, hh:mm a').format(txn.createdAt),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ],
          ),
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
