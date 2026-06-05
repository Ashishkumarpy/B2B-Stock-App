import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/transaction.dart';
import '../../providers/transactions_provider.dart';
import '../../providers/api_client_provider.dart';
import '../../widgets/connection_warning.dart';
import '../../widgets/skeleton_loading.dart';
import '../../widgets/transaction_activity_card.dart';

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
  ConsumerState<StockActivityScreen> createState() =>
      _StockActivityScreenState();
}

class _StockActivityScreenState extends ConsumerState<StockActivityScreen> {
  DateFilterMode _dateFilter = DateFilterMode.today;
  TypeFilterMode _typeFilter = TypeFilterMode.both;
  DateTime? _customFilterDate;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearchVisible = false;

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
      setState(() {
        _applyInitialParameters();
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    } else {
      _typeFilter = TypeFilterMode.both;
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
    } else {
      _dateFilter = DateFilterMode.today;
      _customFilterDate = null;
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
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[d.month - 1]} ${d.day.toString().padLeft(2, '0')}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final txnsAsync = ref.watch(transactionsProvider);

    final bool isDateFilterActive = _dateFilter != DateFilterMode.all;
    final bool isTypeFilterActive = _typeFilter != TypeFilterMode.both;
    final bool isSearchActive = _searchQuery.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Activity'),
        actions: [
          IconButton(
            tooltip: 'Search activity',
            icon: Icon(
              _isSearchVisible ? Icons.search_off_rounded : Icons.search,
              color: isSearchActive ? AppTheme.primary : AppTheme.textSecondary,
            ),
            onPressed: () {
              setState(() {
                _isSearchVisible = !_isSearchVisible;
                if (!_isSearchVisible && _searchQuery.isNotEmpty) {
                  _searchController.clear();
                  _searchQuery = '';
                }
              });
            },
          ),

          // Date Filter Popup Menu
          PopupMenuButton<DateFilterMode>(
            icon: Icon(
              Icons.calendar_today_rounded,
              color: isDateFilterActive
                  ? AppTheme.primary
                  : AppTheme.textSecondary,
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
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<DateFilterMode>>[
              PopupMenuItem<DateFilterMode>(
                value: DateFilterMode.today,
                child: Row(
                  children: [
                    Icon(
                      Icons.today_rounded,
                      size: 18,
                      color: _dateFilter == DateFilterMode.today
                          ? AppTheme.primary
                          : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    const Text('Today',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
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
                      color: _dateFilter == DateFilterMode.all
                          ? AppTheme.primary
                          : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    const Text('All Time',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
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
                      color: _dateFilter == DateFilterMode.custom
                          ? AppTheme.primary
                          : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _customFilterDate != null
                          ? _formatDate(_customFilterDate!)
                          : 'Choose Date...',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
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
              color: isTypeFilterActive
                  ? AppTheme.primary
                  : AppTheme.textSecondary,
            ),
            tooltip: 'Filter by Type',
            onSelected: (TypeFilterMode mode) {
              setState(() {
                _typeFilter = mode;
              });
            },
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<TypeFilterMode>>[
              PopupMenuItem<TypeFilterMode>(
                value: TypeFilterMode.both,
                child: Row(
                  children: [
                    Icon(
                      Icons.swap_vert_rounded,
                      size: 18,
                      color: _typeFilter == TypeFilterMode.both
                          ? AppTheme.primary
                          : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    const Text('All Types',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
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
                      color: _typeFilter == TypeFilterMode.stockIn
                          ? AppTheme.primary
                          : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    const Text('Stock In Only',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
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
                      color: _typeFilter == TypeFilterMode.stockOut
                          ? AppTheme.primary
                          : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    const Text('Stock Out Only',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
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
        error: (error, _) => ConnectionWarning(
          error: error,
          onRetry: () =>
              ref.read(transactionsProvider.notifier).fetchTransactions(),
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
          } else if (_dateFilter == DateFilterMode.custom &&
              _customFilterDate != null) {
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

          // 3. Search Filter
          final query = _searchQuery.trim().toLowerCase();
          if (query.isNotEmpty) {
            filteredTxns = filteredTxns.where((t) {
              final searchable = [
                t.productCode,
                t.productName,
                t.workerName,
                TransactionActivityCard.extractCustomerName(t.notes),
                t.warehouseName ?? '',
                t.colorName ?? '',
                t.notes ?? '',
                t.quantity.toString(),
                t.cartons?.toString() ?? '',
              ].join(' ').toLowerCase();
              return searchable.contains(query);
            }).toList();
          }

          // Prepare Status Labels
          final String dateText;
          if (_dateFilter == DateFilterMode.today) {
            dateText = "Today";
          } else if (_dateFilter == DateFilterMode.all) {
            dateText = "All Time";
          } else if (_dateFilter == DateFilterMode.custom &&
              _customFilterDate != null) {
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

          final headerText = "Showing: $typeText - $dateText";

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                color: AppTheme.primary.withValues(alpha: 0.05),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Row(
                            children: [
                              const Icon(Icons.tune_rounded,
                                  size: 15, color: AppTheme.primary),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  headerText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_dateFilter != DateFilterMode.today ||
                            _typeFilter != TypeFilterMode.both ||
                            isSearchActive)
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _dateFilter = DateFilterMode.today;
                                _typeFilter = TypeFilterMode.both;
                                _customFilterDate = null;
                                _searchController.clear();
                                _searchQuery = '';
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
                    if (_isSearchVisible) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _searchController,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                          });
                        },
                        decoration: InputDecoration(
                          isDense: true,
                          hintText:
                              'Search code, product, worker, warehouse...',
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: isSearchActive
                              ? IconButton(
                                  tooltip: 'Clear search',
                                  icon:
                                      const Icon(Icons.close_rounded, size: 18),
                                  onPressed: () {
                                    setState(() {
                                      _searchController.clear();
                                      _searchQuery = '';
                                    });
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: AppTheme.surfaceColor(context),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: AppTheme.borderColor(context)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: AppTheme.borderColor(context)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: AppTheme.primary),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: filteredTxns.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history_rounded,
                                size: 48,
                                color: Colors.grey.withValues(alpha: 0.4)),
                            const SizedBox(height: 12),
                            Text(
                              'No transactions matches the filter.',
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => ref
                            .read(transactionsProvider.notifier)
                            .fetchTransactions(),
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
    final workerName =
        txn.workerName.isEmpty ? 'Unknown Worker' : txn.workerName;

    return TransactionActivityCard(
      transaction: txn,
      onTap: () => context.push('/products/${txn.productId}'),
      actionMenu: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        icon: const Icon(
          LucideIcons.moreVertical,
          size: 20,
          color: AppTheme.textMuted,
        ),
        onSelected: (value) async {
          if (value == 'edit') {
            final customerName =
                TransactionActivityCard.extractCustomerName(txn.notes);
            final query = <String, String>{
              'transactionId': txn.id,
              'createdAt': txn.createdAt.toIso8601String(),
              'productId': txn.productId,
              'type': isIn ? 'in' : 'out',
              'colorName': txn.colorName?.trim().isNotEmpty == true
                  ? txn.colorName!.trim()
                  : 'Default',
              'quantity': txn.quantity.toString(),
              'notes': txn.notes ?? '',
              'recordedBy': workerName,
            };
            if (txn.workerId.isNotEmpty) {
              query['workerId'] = txn.workerId;
            }
            if (txn.warehouseId?.trim().isNotEmpty == true) {
              query['warehouseId'] = txn.warehouseId!.trim();
            }
            if (txn.cartons != null && txn.cartons! > 0) {
              query['cartons'] = txn.cartons.toString();
            }
            if (txn.pcsPerCarton != null && txn.pcsPerCarton! > 0) {
              query['pcsPerCarton'] = txn.pcsPerCarton.toString();
            }
            if (customerName.isNotEmpty) {
              query['customerName'] = customerName;
            }
            context.push(
                Uri(path: '/stock-entry', queryParameters: query).toString());
            return;
          }
          if (value == 'reverse') {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Reverse Transaction?'),
                content: const Text(
                  'This will create an opposite stock entry to cancel this transaction. Continue?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Reverse'),
                  ),
                ],
              ),
            );
            if (confirmed != true) return;
            try {
              final client = ref.read(apiClientProvider);
              await client.post('/transactions/${txn.id}/reverse', {});
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Transaction reversed successfully.'),
                    backgroundColor: AppTheme.success,
                  ),
                );
              }
              ref.read(transactionsProvider.notifier).fetchTransactions();
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to reverse: $e'),
                    backgroundColor: AppTheme.danger,
                  ),
                );
              }
            }
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem<String>(
            value: 'edit',
            child: Row(
              children: [
                Icon(LucideIcons.edit, size: 17),
                SizedBox(width: 10),
                Text('Edit'),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'reverse',
            child: Row(
              children: [
                Icon(LucideIcons.rotateCcw, size: 17),
                SizedBox(width: 10),
                Text('Reverse'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
