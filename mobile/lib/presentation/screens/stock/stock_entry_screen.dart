import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../providers/products_provider.dart';
import '../../providers/api_client_provider.dart';
import '../../providers/warehouses_provider.dart';
import '../../providers/auth_provider.dart';
import '../../../domain/entities/product.dart';

class StockEntryScreen extends ConsumerStatefulWidget {
  final String? productId;
  final TransactionType? initialType;
  final String? initialColorName;
  final String? initialWarehouseId;
  final int? initialQuantity;
  final int? initialCartons;
  final int? initialPcsPerCarton;
  final String? initialNotes;
  final String? initialRecordedBy;
  final String? initialCustomerName;

  const StockEntryScreen({
    super.key,
    this.productId,
    this.initialType,
    this.initialColorName,
    this.initialWarehouseId,
    this.initialQuantity,
    this.initialCartons,
    this.initialPcsPerCarton,
    this.initialNotes,
    this.initialRecordedBy,
    this.initialCustomerName,
  });

  @override
  ConsumerState<StockEntryScreen> createState() => _StockEntryScreenState();
}

class _StockEntryScreenState extends ConsumerState<StockEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _qtyController = TextEditingController();
  final _cartonsController = TextEditingController();
  final _pcsPerCartonController = TextEditingController();
  final _notesController = TextEditingController();
  final _recordedByController = TextEditingController();
  final _customerController = TextEditingController();

  Product? _selectedProduct;
  String _selectedColor = 'Default';
  TransactionType _type = TransactionType.stockIn;
  String? _selectedWarehouseId;
  Set<String> _stockOutWarehouseIdsWithStock = <String>{};
  bool _isLoadingStockOutWarehouses = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialType != null) _type = widget.initialType!;

    // Auto-select product if ID is provided
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentUser = ref.read(currentUserProvider);
      setState(() {
        _recordedByController.text =
            widget.initialRecordedBy ?? currentUser?.name ?? 'Ashish';
        if (widget.initialNotes != null) {
          _notesController.text = widget.initialNotes!;
        }
        if (widget.initialCustomerName != null) {
          _customerController.text = widget.initialCustomerName!;
        }
        if (widget.initialQuantity != null && widget.initialQuantity! > 0) {
          _qtyController.text = widget.initialQuantity.toString();
        }
        if (widget.initialCartons != null && widget.initialCartons! > 0) {
          _cartonsController.text = widget.initialCartons.toString();
        }
        if (widget.initialPcsPerCarton != null &&
            widget.initialPcsPerCarton! > 0) {
          _pcsPerCartonController.text = widget.initialPcsPerCarton.toString();
        }
        if (widget.initialWarehouseId != null &&
            widget.initialWarehouseId!.isNotEmpty) {
          _selectedWarehouseId = widget.initialWarehouseId;
        }
      });

      if (widget.productId != null) {
        final products = ref.read(productsProvider).value ?? [];
        final match =
            products.where((p) => p.id == widget.productId).firstOrNull;
        if (match != null) {
          final defaultPcsPerCarton =
              (match.pcsPerCarton != null && match.pcsPerCarton! > 0)
                  ? match.pcsPerCarton!
                  : 1;
          setState(() {
            _selectedProduct = match;
            if (match.colorStocks.isNotEmpty) {
              final preferredColor = widget.initialColorName?.trim();
              final hasPreferredColor = preferredColor != null &&
                  match.colorStocks.any((c) => c.color == preferredColor);
              _selectedColor = hasPreferredColor
                  ? preferredColor
                  : match.colorStocks.first.color;
            }
            if (_pcsPerCartonController.text.trim().isEmpty) {
              _pcsPerCartonController.text = defaultPcsPerCarton.toString();
            }
          });
          _refreshStockOutWarehouses();
        }
      }
    });

    _cartonsController.addListener(_calculateTotal);
    _pcsPerCartonController.addListener(_calculateTotal);
  }

  void _calculateTotal() {
    final cartons = int.tryParse(_cartonsController.text) ?? 0;
    final pcs = int.tryParse(_pcsPerCartonController.text) ?? 0;
    if (cartons > 0 && pcs > 0) {
      setState(() {
        _qtyController.text = (cartons * pcs).toString();
      });
    }
  }

  Future<void> _refreshStockOutWarehouses() async {
    if (_type != TransactionType.stockOut || _selectedProduct == null) {
      if (!mounted) return;
      setState(() {
        _stockOutWarehouseIdsWithStock = <String>{};
        _isLoadingStockOutWarehouses = false;
      });
      return;
    }

    setState(() {
      _isLoadingStockOutWarehouses = true;
    });

    try {
      final client = ref.read(apiClientProvider);
      final productId = Uri.encodeQueryComponent(_selectedProduct!.id);
      final colorName = Uri.encodeQueryComponent(_selectedColor.trim());
      final response = await client.get(
        '/warehouses/stock-options?product_id=$productId&color_name=$colorName',
      );
      final list = (response is Map ? response['data'] : null) as List? ?? const [];
      final ids = list
          .map((row) => (row as Map?)?['warehouse_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      if (!mounted) return;
      setState(() {
        _stockOutWarehouseIdsWithStock = ids;
        if (_selectedWarehouseId != null &&
            !_stockOutWarehouseIdsWithStock.contains(_selectedWarehouseId)) {
          _selectedWarehouseId = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stockOutWarehouseIdsWithStock = <String>{};
        _selectedWarehouseId = null;
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoadingStockOutWarehouses = false;
      });
    }
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _cartonsController.dispose();
    _pcsPerCartonController.dispose();
    _notesController.dispose();
    _recordedByController.dispose();
    _customerController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Please select a product and fill all required fields.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    final qty = int.tryParse(_qtyController.text) ?? 0;
    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Total Quantity must be greater than 0.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    // Validation for Stock Out
    if (_type == TransactionType.stockOut) {
      if (_selectedWarehouseId == null || _selectedWarehouseId!.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a warehouse for Stock Out.'),
            backgroundColor: AppTheme.danger,
          ),
        );
        return;
      }

      final availableQty = _selectedProduct!.colorStocks.isNotEmpty
          ? (_selectedProduct!.colorStocks
                  .where((c) => c.color == _selectedColor)
                  .firstOrNull
                  ?.quantity ??
              0)
          : _selectedProduct!.quantity;

      if (qty > availableQty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Only $availableQty units available for color "$_selectedColor". Cannot dispatch more than available stock.'),
            backgroundColor: AppTheme.danger,
          ),
        );
        return;
      }
    }

    setState(() => _isSubmitting = true);
    try {
      final client = ref.read(apiClientProvider);

      final workerName = _recordedByController.text.trim().isNotEmpty
          ? _recordedByController.text.trim()
          : 'Ashish';

      final cartonsText = _cartonsController.text.trim();
      final pcsText = _pcsPerCartonController.text.trim();
      final fallbackPcsPerCarton = (_selectedProduct?.pcsPerCarton != null &&
              _selectedProduct!.pcsPerCarton! > 0)
          ? _selectedProduct!.pcsPerCarton!
          : 1;
      final parsedPcsPerCarton = int.tryParse(pcsText);
      final resolvedPcsPerCarton =
          (parsedPcsPerCarton != null && parsedPcsPerCarton > 0)
              ? parsedPcsPerCarton
              : fallbackPcsPerCarton;
      String finalNotes = _notesController.text.trim();

      final customerText = _customerController.text.trim();
      if (_type == TransactionType.stockOut && customerText.isNotEmpty) {
        finalNotes = finalNotes.isNotEmpty
            ? 'Customer: $customerText | $finalNotes'
            : 'Customer: $customerText';
      }

      await client.post('/transactions', {
        'product_id': _selectedProduct!.id,
        'product_name': _selectedProduct!.name,
        'type': _type == TransactionType.stockIn ? 'stock_in' : 'stock_out',
        'quantity': qty,
        'color_name': _selectedColor,
        'notes': finalNotes,
        'warehouse_id':
            (_selectedWarehouseId == null || _selectedWarehouseId == 'default')
                ? null
                : _selectedWarehouseId,
        'worker_name': workerName,
        if (cartonsText.isNotEmpty) 'cartons': int.tryParse(cartonsText),
        'pcs_per_carton': resolvedPcsPerCarton,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transaction recorded successfully'),
            backgroundColor: AppTheme.success,
          ),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _openProductPicker(List<Product> products) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ProductPickerModal(
        products: products,
        onSelected: (p) {
          final defaultPcsPerCarton =
              (p.pcsPerCarton != null && p.pcsPerCarton! > 0)
                  ? p.pcsPerCarton!
                  : 1;
          setState(() {
            _selectedProduct = p;
            if (p.colorStocks.isNotEmpty) {
              _selectedColor = p.colorStocks.first.color;
            } else {
              _selectedColor = 'Default';
            }
            _pcsPerCartonController.text = defaultPcsPerCarton.toString();
          });
          _refreshStockOutWarehouses();
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider).value ?? [];
    final warehousesAsync = ref.watch(warehousesProvider);
    final warehouses = warehousesAsync.value ?? [];
    final warehouseOptions =
        (_type == TransactionType.stockOut && _selectedProduct != null && !_isLoadingStockOutWarehouses)
            ? warehouses
                .where((w) => _stockOutWarehouseIdsWithStock
                    .contains(w['id']?.toString() ?? ''))
                .toList()
            : warehouses;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor(context),
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceColor(context),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: AppTheme.primaryTextColor(context), size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Record Stock Movement',
          style: TextStyle(
            color: AppTheme.primaryTextColor(context),
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.close_rounded,
                color: AppTheme.primaryTextColor(context), size: 24),
            onPressed: () => context.pop(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── MOVEMENT TYPE ──
              Text(
                'MOVEMENT TYPE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: AppTheme.mutedTextColor(context),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _type = TransactionType.stockIn);
                        _refreshStockOutWarehouses();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _type == TransactionType.stockIn
                              ? const Color(0xFFECFDF5)
                              : Colors.white,
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusLG),
                          border: Border.all(
                            color: _type == TransactionType.stockIn
                                ? AppTheme.success
                                : const Color(0xFFE2E8F0),
                            width: _type == TransactionType.stockIn ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.arrow_upward_rounded,
                              size: 16,
                              color: _type == TransactionType.stockIn
                                  ? AppTheme.success
                                  : AppTheme.textMuted,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Stock In',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _type == TransactionType.stockIn
                                    ? AppTheme.success
                                    : AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _type = TransactionType.stockOut;
                          if (_selectedProduct != null &&
                              _selectedProduct!.quantity <= 0) {
                            _selectedProduct = null;
                            _selectedColor = 'Default';
                          }
                        });
                        _refreshStockOutWarehouses();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _type == TransactionType.stockOut
                              ? const Color(0xFFFEF2F2)
                              : Colors.white,
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusLG),
                          border: Border.all(
                            color: _type == TransactionType.stockOut
                                ? AppTheme.danger
                                : const Color(0xFFE2E8F0),
                            width: _type == TransactionType.stockOut ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.arrow_downward_rounded,
                              size: 16,
                              color: _type == TransactionType.stockOut
                                  ? AppTheme.danger
                                  : AppTheme.textMuted,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Stock Out',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _type == TransactionType.stockOut
                                    ? AppTheme.danger
                                    : AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── PRODUCT SELECTION ──
              Text(
                'PRODUCT *',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: AppTheme.mutedTextColor(context),
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () {
                  final filteredProducts = _type == TransactionType.stockOut
                      ? products.where((p) => p.quantity > 0).toList()
                      : products;
                  _openProductPicker(filteredProducts);
                },
                borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor(context),
                    borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                    border: Border.all(color: AppTheme.borderColor(context)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: _selectedProduct != null
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedProduct!.code,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _selectedProduct!.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          AppTheme.secondaryTextColor(context),
                                    ),
                                  ),
                                ],
                              )
                            : Text(
                                'Choose product from folders...',
                                style: TextStyle(
                                  color: AppTheme.mutedTextColor(context),
                                  fontSize: 14,
                                ),
                              ),
                      ),
                      Row(
                        children: [
                          if (_selectedProduct != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryLight,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Available: ${_selectedProduct!.quantity}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: AppTheme.mutedTextColor(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── WAREHOUSE & COLOR ROW ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Warehouse Dropdown
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'WAREHOUSE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: AppTheme.mutedTextColor(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceColor(context),
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusLG),
                            border: Border.all(
                                color: AppTheme.borderColor(context)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedWarehouseId,
                              isExpanded: true,
                              hint: Text(
                                'Select warehouse',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.mutedTextColor(context),
                                ),
                              ),
                              icon: Icon(Icons.keyboard_arrow_down_rounded,
                                  color: AppTheme.mutedTextColor(context)),
                              items: (_type == TransactionType.stockOut &&
                                      _selectedProduct != null &&
                                      !_isLoadingStockOutWarehouses &&
                                      warehouseOptions.isEmpty)
                                  ? [
                                      DropdownMenuItem(
                                        value: 'default',
                                        child: Text(
                                          'No warehouse has stock for this color',
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: AppTheme.primaryTextColor(
                                                  context)),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ]
                                  : warehouses.isEmpty
                                  ? [
                                      DropdownMenuItem(
                                        value: 'default',
                                        child: Text(
                                          'Main Warehouse — Primary Location',
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: AppTheme.primaryTextColor(
                                                  context)),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ]
                                  : warehouseOptions.map((w) {
                                      final name = w['name']?.toString() ??
                                          'Main Warehouse';
                                      final loc =
                                          w['location']?.toString() ?? '';
                                      final display = loc.isNotEmpty
                                          ? '$name — $loc'
                                          : name;
                                      return DropdownMenuItem(
                                        value: w['id']?.toString(),
                                        child: Text(
                                          display,
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: AppTheme.primaryTextColor(
                                                  context)),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    }).toList(),
                              onChanged: (val) {
                                if (val == 'default') return;
                                setState(() {
                                  _selectedWarehouseId = val;
                                });
                              },
                            ),
                          ),
                        ),
                        if (_type == TransactionType.stockOut) ...[
                          const SizedBox(height: 6),
                          Text(
                            _isLoadingStockOutWarehouses
                                ? 'Checking stock availability...'
                                : 'Only warehouses with available stock are shown.',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.mutedTextColor(context),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Color Dropdown
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'COLOR *',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: AppTheme.mutedTextColor(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceColor(context),
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusLG),
                            border: Border.all(
                                color: AppTheme.borderColor(context)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedProduct != null &&
                                      _selectedProduct!.colorStocks.isNotEmpty
                                  ? (_selectedProduct!.colorStocks
                                          .any((c) => c.color == _selectedColor)
                                      ? _selectedColor
                                      : _selectedProduct!
                                          .colorStocks.first.color)
                                  : 'Default',
                              isExpanded: true,
                              icon: Icon(Icons.keyboard_arrow_down_rounded,
                                  color: AppTheme.mutedTextColor(context)),
                              items: _selectedProduct != null &&
                                      _selectedProduct!.colorStocks.isNotEmpty
                                  ? _selectedProduct!.colorStocks.map((c) {
                                      return DropdownMenuItem(
                                        value: c.color,
                                        child: Text(
                                          '${c.color} (${c.quantity})',
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: AppTheme.primaryTextColor(
                                                  context)),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    }).toList()
                                  : [
                                      DropdownMenuItem(
                                        value: 'Default',
                                        child: Text(
                                          'Default',
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: AppTheme.primaryTextColor(
                                                  context)),
                                        ),
                                      ),
                                    ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedColor = val;
                                  });
                                  _refreshStockOutWarehouses();
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── CARTONS, PCS & TOTAL QUANTITY ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cartons Input
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CARTONS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: AppTheme.mutedTextColor(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _cartonsController,
                          keyboardType: TextInputType.number,
                          style: TextStyle(
                              fontSize: 14,
                              color: AppTheme.primaryTextColor(context)),
                          decoration: InputDecoration(
                            hintText: 'e.g. 5',
                            hintStyle: TextStyle(
                                color: AppTheme.mutedTextColor(context),
                                fontSize: 13),
                            fillColor: AppTheme.inputFillColor(context),
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 14),
                            enabledBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusLG),
                              borderSide: BorderSide(
                                  color: AppTheme.borderColor(context)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusLG),
                              borderSide: const BorderSide(
                                  color: AppTheme.primary, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Pcs / Carton Input
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PCS / CARTON',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: AppTheme.mutedTextColor(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _pcsPerCartonController,
                          keyboardType: TextInputType.number,
                          style: TextStyle(
                              fontSize: 14,
                              color: AppTheme.primaryTextColor(context)),
                          decoration: InputDecoration(
                            hintText: 'e.g. 20',
                            hintStyle: TextStyle(
                                color: AppTheme.mutedTextColor(context),
                                fontSize: 13),
                            fillColor: AppTheme.inputFillColor(context),
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 14),
                            enabledBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusLG),
                              borderSide: BorderSide(
                                  color: AppTheme.borderColor(context)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusLG),
                              borderSide: const BorderSide(
                                  color: AppTheme.primary, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Total Quantity Input
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TOTAL QTY *',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: AppTheme.mutedTextColor(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _qtyController,
                          keyboardType: TextInputType.number,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryTextColor(context)),
                          validator: (val) {
                            if (val == null || val.isEmpty) return 'Required';
                            if (int.tryParse(val) == null) return 'Invalid';
                            return null;
                          },
                          decoration: InputDecoration(
                            hintText: 'e.g. 100',
                            hintStyle: TextStyle(
                                color: AppTheme.mutedTextColor(context),
                                fontSize: 13),
                            fillColor: AppTheme.inputFillColor(context),
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 14),
                            enabledBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusLG),
                              borderSide: BorderSide(
                                  color: AppTheme.borderColor(context)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusLG),
                              borderSide: const BorderSide(
                                  color: AppTheme.primary, width: 2),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusLG),
                              borderSide:
                                  const BorderSide(color: AppTheme.danger),
                            ),
                            focusedErrorBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusLG),
                              borderSide: const BorderSide(
                                  color: AppTheme.danger, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── RECORDED BY * ──
              Text(
                'RECORDED BY *',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: AppTheme.mutedTextColor(context),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _recordedByController,
                style: TextStyle(
                    fontSize: 14, color: AppTheme.primaryTextColor(context)),
                validator: (val) => val == null || val.trim().isEmpty
                    ? 'Recorded By is required'
                    : null,
                decoration: InputDecoration(
                  hintText: 'Ashish',
                  fillColor: AppTheme.inputFillColor(context),
                  filled: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                    borderSide:
                        BorderSide(color: AppTheme.borderColor(context)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                    borderSide:
                        const BorderSide(color: AppTheme.primary, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              if (_type == TransactionType.stockOut) ...[
                Text(
                  'CUSTOMER NAME',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: AppTheme.mutedTextColor(context),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _customerController,
                  style: TextStyle(
                      fontSize: 14, color: AppTheme.primaryTextColor(context)),
                  decoration: InputDecoration(
                    hintText: 'Enter customer name (optional)',
                    fillColor: AppTheme.inputFillColor(context),
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                      borderSide:
                          BorderSide(color: AppTheme.borderColor(context)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                      borderSide:
                          const BorderSide(color: AppTheme.primary, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // ── NOTES ──
              Text(
                'NOTES (OPTIONAL)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: AppTheme.mutedTextColor(context),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                style: TextStyle(
                    fontSize: 14, color: AppTheme.primaryTextColor(context)),
                decoration: InputDecoration(
                  hintText: 'Reason, batch number, etc.',
                  hintStyle: TextStyle(
                      color: AppTheme.mutedTextColor(context), fontSize: 13),
                  fillColor: AppTheme.inputFillColor(context),
                  filled: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                    borderSide:
                        BorderSide(color: AppTheme.borderColor(context)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                    borderSide:
                        const BorderSide(color: AppTheme.primary, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // ── ACTION BUTTONS ──
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _type == TransactionType.stockIn
                      ? AppTheme.success
                      : AppTheme.danger,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                  ),
                  minimumSize: const Size(double.infinity, 52),
                  elevation: 0,
                ),
                child: _isSubmitting
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _type == TransactionType.stockIn
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _type == TransactionType.stockIn
                                ? '↑ Record Stock In'
                                : '↓ Record Stock Out',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 12),

              // Cancel like admin
              OutlinedButton(
                onPressed: () => context.pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                  side: BorderSide(color: AppTheme.borderColor(context)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                  ),
                  minimumSize: const Size(double.infinity, 52),
                ),
                child: Text(
                  'Cancel',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProductPickerModal extends StatefulWidget {
  final List<Product> products;
  final ValueChanged<Product> onSelected;

  const ProductPickerModal({
    super.key,
    required this.products,
    required this.onSelected,
  });

  @override
  State<ProductPickerModal> createState() => _ProductPickerModalState();
}

class _ProductPickerModalState extends State<ProductPickerModal> {
  String? _selectedCategory;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Group products by category
    final categories = <String, int>{};
    for (final p in widget.products) {
      final cat = p.category;
      categories[cat] = (categories[cat] ?? 0) + 1;
    }

    final categoryList = categories.keys.toList()..sort();

    // Filter products
    final filteredProducts = widget.products.where((p) {
      if (_selectedCategory != null) {
        return p.category == _selectedCategory;
      }
      return true;
    }).toList();

    final displayProducts = _searchQuery.isNotEmpty
        ? widget.products.where((p) {
            final q = _searchQuery.toLowerCase();
            return p.name.toLowerCase().contains(q) ||
                p.code.toLowerCase().contains(q);
          }).toList()
        : filteredProducts;

    displayProducts.sort((a, b) => a.code.compareTo(b.code));

    final isSearching = _searchQuery.isNotEmpty;
    final isRoot = _selectedCategory == null && !isSearching;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                if (!isRoot) ...[
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded,
                        color: AppTheme.primaryTextColor(context), size: 20),
                    onPressed: () {
                      setState(() {
                        if (isSearching) {
                          _searchQuery = '';
                          _searchController.clear();
                        } else {
                          _selectedCategory = null;
                        }
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  isSearching
                      ? 'Search Results'
                      : (_selectedCategory ?? 'Choose product from folders...'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primaryTextColor(context),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      color: AppTheme.primaryTextColor(context)),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
              style: TextStyle(
                  fontSize: 14, color: AppTheme.primaryTextColor(context)),
              decoration: InputDecoration(
                hintText: 'Search products by name or code...',
                hintStyle: TextStyle(
                    color: AppTheme.mutedTextColor(context), fontSize: 13),
                prefixIcon: Icon(Icons.search_rounded,
                    color: AppTheme.mutedTextColor(context), size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear_rounded,
                            color: AppTheme.mutedTextColor(context), size: 20),
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                            _searchController.clear();
                          });
                        },
                      )
                    : null,
                fillColor: AppTheme.inputFillColor(context),
                filled: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                  borderSide: BorderSide(color: AppTheme.borderColor(context)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                  borderSide:
                      const BorderSide(color: AppTheme.primary, width: 2),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Main body scroll area
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: isRoot
                  ? GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio:
                            1.0, // Perfect square layout to gain more vertical height
                      ),
                      itemCount: categoryList.length,
                      itemBuilder: (context, index) {
                        final cat = categoryList[index];
                        final count = categories[cat] ?? 0;
                        return InkWell(
                          onTap: () => setState(() => _selectedCategory = cat),
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusLG),
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceColor(context),
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusLG),
                              border: Border.all(
                                  color: AppTheme.borderColor(context)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.02),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 12),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '📁',
                                  style: TextStyle(fontSize: 32),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  cat,
                                  textAlign: TextAlign.center,
                                  maxLines:
                                      1, // Compact 1 line to completely prevent overflows
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: AppTheme.primaryTextColor(context),
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryLight,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    '$count items',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    )
                  : displayProducts.isEmpty
                      ? Container(
                          padding: const EdgeInsets.all(32),
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inventory_2_outlined,
                                  size: 48,
                                  color: AppTheme.mutedTextColor(context)),
                              const SizedBox(height: 12),
                              Text(
                                'No products found',
                                style: TextStyle(
                                    color: AppTheme.mutedTextColor(context),
                                    fontSize: 13),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: displayProducts.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final p = displayProducts[index];
                            return InkWell(
                              onTap: () => widget.onSelected(p),
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusLG),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceColor(context),
                                  borderRadius:
                                      BorderRadius.circular(AppTheme.radiusLG),
                                  border: Border.all(
                                      color: AppTheme.borderColor(context)),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.01),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 14),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            p.code,
                                            style: TextStyle(
                                              fontFamily: 'monospace',
                                              fontWeight: FontWeight.w900,
                                              fontSize: 13,
                                              color: AppTheme.primary,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            p.name,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color:
                                                  AppTheme.secondaryTextColor(
                                                      context),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryLight,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Qty: ${p.quantity}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                          color: AppTheme.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }
}
