import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/transaction.dart';
import '../../providers/transactions_provider.dart';
import '../../widgets/skeleton_loading.dart';

enum DateFilterMode { today, all, custom }
enum TypeFilterMode { both, stockIn, stockOut }

class StockActivityScreen extends ConsumerStatefulWidget {
  final String? initialType;
  final String? initialDateMode;
  final String? initialDate;

  const StockActivityScreen({
    super.key,
    this.initialType,
    this.initialDateMode,
    this.initialDate,
  });

  @override
  ConsumerState<StockActivityScreen> createState() => _StockActivityScreenState();
}

class _StockActivityScreenState extends ConsumerState<StockActivityScreen> {
  DateFilterMode _dateFilter = DateFilterMode.today;
  TypeFilterMode _typeFilter = TypeFilterMode.both;
  DateTime? _customFilterDate;

  @override
  void initState() {
    super.initState();
    _applyInitialParameters();
  }

  @override
  void didUpdateWidget(covariant StockActivityScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialType != oldWidget.initialType ||
        widget.initialDateMode != oldWidget.initialDateMode ||
        widget.initialDate != oldWidget.initialDate) {
      _applyInitialParameters();
    }
  }

  void _applyInitialParameters() {
    if (widget.initialType != null) {
      if (widget.initialType == 'stockIn') {
        _typeFilter = TypeFilterMode.stockIn;
      } else if (widget.initialType == 'stockOut') {
        _typeFilter = TypeFilterMode.stockOut;
      } else if (widget.initialType == 'both') {
        _typeFilter = TypeFilterMode.both;
      }
    }
    
    if (widget.initialDateMode != null) {
      if (widget.initialDateMode == 'today') {
        _dateFilter = DateFilterMode.today;
        _customFilterDate = null;
      } else if (widget.initialDateMode == 'all') {
        _dateFilter = DateFilterMode.all;
        _customFilterDate = null;
      } else if (widget.initialDateMode == 'custom') {
        _dateFilter = DateFilterMode.custom;
      }
    }
    
    if (widget.initialDate != null) {
      final parsed = DateTime.tryParse(widget.initialDate!);
      if (parsed != null) {
        _customFilterDate = parsed;
        _dateFilter = DateFilterMode.custom;
      }
    }
  }

  String _formatDate(DateTime d) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.day.toString().padLeft(2, '0')}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final txnsAsync = ref.watch(transactionsProvider);

    final bool isDateFilterActive = _dateFilter != DateFilterMode.all;
    final bool isTypeFilterActive = _typeFilter != TypeFilterMode.both;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Activity'),
        actions: [
          // Date Filter Popup Menu
          PopupMenuButton<DateFilterMode>(
            icon: Icon(
              Icons.calendar_today_rounded,
              color: isDateFilterActive ? AppTheme.primary : AppTheme.textSecondary,
            ),
            tooltip: 'Filter by Date',
            onSelected: (DateFilterMode mode) async {
              if (mode == DateFilterMode.custom) {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _customFilterDate ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) {
                  setState(() {
                    _dateFilter = DateFilterMode.custom;
                    _customFilterDate = picked;
                  });
                }
              } else {
                setState(() {
                  _dateFilter = mode;
                  _customFilterDate = null;
                });
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<DateFilterMode>>[
              PopupMenuItem<DateFilterMode>(
                value: DateFilterMode.today,
                child: Row(
                  children: [
                    Icon(
                      Icons.today_rounded,
                      size: 18,
                      color: _dateFilter == DateFilterMode.today ? AppTheme.primary : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    const Text('Today', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              PopupMenuItem<DateFilterMode>(
                value: DateFilterMode.all,
                child: Row(
                  children: [
                    Icon(
                      Icons.all_inbox_rounded,
                      size: 18,
                      color: _dateFilter == DateFilterMode.all ? AppTheme.primary : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    const Text('All Time', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              PopupMenuItem<DateFilterMode>(
                value: DateFilterMode.custom,
                child: Row(
                  children: [
                    Icon(
                      Icons.date_range_rounded,
                      size: 18,
                      color: _dateFilter == DateFilterMode.custom ? AppTheme.primary : AppTheme.textSecondary,
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
          
          // Type Filter Popup Menu
          PopupMenuButton<TypeFilterMode>(
            icon: Icon(
              Icons.filter_list_rounded,
              color: isTypeFilterActive ? AppTheme.primary : AppTheme.textSecondary,
            ),
            tooltip: 'Filter by Type',
            onSelected: (TypeFilterMode mode) {
              setState(() {
                _typeFilter = mode;
              });
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<TypeFilterMode>>[
              PopupMenuItem<TypeFilterMode>(
                value: TypeFilterMode.both,
                child: Row(
                  children: [
                    Icon(
                      Icons.swap_vert_rounded,
                      size: 18,
                      color: _typeFilter == TypeFilterMode.both ? AppTheme.primary : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    const Text('All Types', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              PopupMenuItem<TypeFilterMode>(
                value: TypeFilterMode.stockIn,
                child: Row(
                  children: [
                    Icon(
                      Icons.south_west_rounded,
                      size: 18,
                      color: _typeFilter == TypeFilterMode.stockIn ? AppTheme.primary : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    const Text('Stock In Only', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              PopupMenuItem<TypeFilterMode>(
                value: TypeFilterMode.stockOut,
                child: Row(
                  children: [
                    Icon(
                      Icons.north_east_rounded,
                      size: 18,
                      color: _typeFilter == TypeFilterMode.stockOut ? AppTheme.primary : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    const Text('Stock Out Only', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
          
          // 1. Date Filter
          if (_dateFilter == DateFilterMode.today) {
            final now = DateTime.now();
            filteredTxns = filteredTxns.where((t) {
              return t.createdAt.year == now.year &&
                  t.createdAt.month == now.month &&
                  t.createdAt.day == now.day;
            }).toList();
          } else if (_dateFilter == DateFilterMode.custom && _customFilterDate != null) {
            filteredTxns = filteredTxns.where((t) {
              return t.createdAt.year == _customFilterDate!.year &&
                  t.createdAt.month == _customFilterDate!.month &&
                  t.createdAt.day == _customFilterDate!.day;
            }).toList();
          }

          // 2. Type Filter
          if (_typeFilter == TypeFilterMode.stockIn) {
            filteredTxns = filteredTxns.where((t) => t.isStockIn).toList();
          } else if (_typeFilter == TypeFilterMode.stockOut) {
            filteredTxns = filteredTxns.where((t) => t.isStockOut).toList();
          }

          // Prepare Status Labels
          final String dateText;
          if (_dateFilter == DateFilterMode.today) {
            dateText = "Today";
          } else if (_dateFilter == DateFilterMode.all) {
            dateText = "All Time";
          } else if (_dateFilter == DateFilterMode.custom && _customFilterDate != null) {
            dateText = _formatDate(_customFilterDate!);
          } else {
            dateText = "";
          }

          final String typeText;
          if (_typeFilter == TypeFilterMode.stockIn) {
            typeText = "Stock In";
          } else if (_typeFilter == TypeFilterMode.stockOut) {
            typeText = "Stock Out";
          } else {
            typeText = "All Activities";
          }

          final headerText = "Showing: $typeText • $dateText";

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
                    if (_dateFilter != DateFilterMode.today || _typeFilter != TypeFilterMode.both)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _dateFilter = DateFilterMode.today;
                            _typeFilter = TypeFilterMode.both;
                            _customFilterDate = null;
                          });
                        },
                        child: const Text(
                          'Reset',
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
