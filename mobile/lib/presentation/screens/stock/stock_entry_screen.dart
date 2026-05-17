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

  const StockEntryScreen({
    super.key,
    this.productId,
    this.initialType,
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

  Product? _selectedProduct;
  String _selectedColor = 'Default';
  TransactionType _type = TransactionType.stockIn;
  String? _selectedWarehouseId;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialType != null) _type = widget.initialType!;

    // Auto-select product if ID is provided
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentUser = ref.read(currentUserProvider);
      setState(() {
        _recordedByController.text = currentUser?.name ?? 'Ashish';
      });

      if (widget.productId != null) {
        final products = ref.read(productsProvider).value ?? [];
        final match =
            products.where((p) => p.id == widget.productId).firstOrNull;
        if (match != null) {
          setState(() {
            _selectedProduct = match;
            if (match.colorStocks.isNotEmpty) {
              _selectedColor = match.colorStocks.first.color;
            }
          });
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

  @override
  void dispose() {
    _qtyController.dispose();
    _cartonsController.dispose();
    _pcsPerCartonController.dispose();
    _notesController.dispose();
    _recordedByController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a product and fill all required fields.'),
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

      await client.post('/transactions', {
        'product_id': _selectedProduct!.id,
        'product_name': _selectedProduct!.name,
        'type': _type == TransactionType.stockIn ? 'stock_in' : 'stock_out',
        'quantity': qty,
        'color_name': _selectedColor,
        'notes': _notesController.text.trim(),
        'warehouse_id': _selectedWarehouseId ?? 'default',
        'worker_name': workerName,
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
          setState(() {
            _selectedProduct = p;
            if (p.colorStocks.isNotEmpty) {
              _selectedColor = p.colorStocks.first.color;
            } else {
              _selectedColor = 'Default';
            }
          });
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

    // Ensure _selectedWarehouseId is initialized
    if (_selectedWarehouseId == null && warehouses.isNotEmpty) {
      _selectedWarehouseId = warehouses.first['id']?.toString();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Record Stock Movement',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: AppTheme.textPrimary, size: 24),
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
              const Text(
                'MOVEMENT TYPE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _type = TransactionType.stockIn),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _type == TransactionType.stockIn
                              ? const Color(0xFFECFDF5)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(AppTheme.radiusLG),
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
                      onTap: () => setState(() => _type = TransactionType.stockOut),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _type == TransactionType.stockOut
                              ? const Color(0xFFFEF2F2)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(AppTheme.radiusLG),
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
              const Text(
                'PRODUCT *',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => _openProductPicker(products),
                borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
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
                                    style: const TextStyle(
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
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              )
                            : const Text(
                                'Choose product from folders...',
                                style: TextStyle(
                                  color: AppTheme.textMuted,
                                  fontSize: 14,
                                ),
                              ),
                      ),
                      Row(
                        children: [
                          if (_selectedProduct != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryLight,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Available: ${_selectedProduct!.quantity}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: AppTheme.textMuted,
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
                        const Text(
                          'WAREHOUSE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedWarehouseId,
                              isExpanded: true,
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.textMuted),
                              items: warehouses.isEmpty
                                  ? [
                                      const DropdownMenuItem(
                                        value: 'default',
                                        child: Text(
                                          'Main Warehouse — Primary Location',
                                          style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ]
                                  : warehouses.map((w) {
                                      final name = w['name']?.toString() ?? 'Main Warehouse';
                                      final loc = w['location']?.toString() ?? '';
                                      final display = loc.isNotEmpty ? '$name — $loc' : name;
                                      return DropdownMenuItem(
                                        value: w['id']?.toString(),
                                        child: Text(
                                          display,
                                          style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    }).toList(),
                              onChanged: (val) {
                                setState(() {
                                  _selectedWarehouseId = val;
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Color Dropdown
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'COLOR *',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedProduct != null &&
                                      _selectedProduct!.colorStocks.isNotEmpty
                                  ? (_selectedProduct!.colorStocks.any((c) => c.color == _selectedColor)
                                      ? _selectedColor
                                      : _selectedProduct!.colorStocks.first.color)
                                  : 'Default',
                              isExpanded: true,
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.textMuted),
                              items: _selectedProduct != null &&
                                      _selectedProduct!.colorStocks.isNotEmpty
                                  ? _selectedProduct!.colorStocks.map((c) {
                                      return DropdownMenuItem(
                                        value: c.color,
                                        child: Text(
                                          '${c.color} (${c.quantity})',
                                          style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    }).toList()
                                  : [
                                      const DropdownMenuItem(
                                        value: 'Default',
                                        child: Text(
                                          'Default',
                                          style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                                        ),
                                      ),
                                    ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedColor = val;
                                  });
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
                        const Text(
                          'CARTONS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _cartonsController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'e.g. 5',
                            hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                            fillColor: Colors.white,
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                              borderSide: const BorderSide(color: AppTheme.primary, width: 2),
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
                        const Text(
                          'PCS / CARTON',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _pcsPerCartonController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'e.g. 20',
                            hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                            fillColor: Colors.white,
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                              borderSide: const BorderSide(color: AppTheme.primary, width: 2),
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
                        const Text(
                          'TOTAL QTY *',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _qtyController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          validator: (val) {
                            if (val == null || val.isEmpty) return 'Required';
                            if (int.tryParse(val) == null) return 'Invalid';
                            return null;
                          },
                          decoration: InputDecoration(
                            hintText: 'e.g. 100',
                            hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                            fillColor: Colors.white,
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                              borderSide: const BorderSide(color: AppTheme.primary, width: 2),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                              borderSide: const BorderSide(color: AppTheme.danger),
                            ),
                            focusedErrorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                              borderSide: const BorderSide(color: AppTheme.danger, width: 2),
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
              const Text(
                'RECORDED BY *',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _recordedByController,
                style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                validator: (val) => val == null || val.trim().isEmpty ? 'Recorded By is required' : null,
                decoration: InputDecoration(
                  hintText: 'Ashish',
                  fillColor: Colors.white,
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                    borderSide: const BorderSide(color: AppTheme.primary, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── NOTES ──
              const Text(
                'NOTES (OPTIONAL)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Reason, batch number, etc.',
                  hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                  fillColor: Colors.white,
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                    borderSide: const BorderSide(color: AppTheme.primary, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // ── ACTION BUTTONS ──
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _type == TransactionType.stockIn ? AppTheme.success : AppTheme.danger,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                  ),
                  minimumSize: const Size(double.infinity, 52),
                  elevation: 0,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _type == TransactionType.stockIn ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _type == TransactionType.stockIn ? '↑ Record Stock In' : '↓ Record Stock Out',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
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
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                  ),
                  minimumSize: const Size(double.infinity, 52),
                ),
                child: const Text(
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
      final cat = p.category ?? 'Uncategorized';
      categories[cat] = (categories[cat] ?? 0) + 1;
    }

    final categoryList = categories.keys.toList()..sort();

    // Filter products
    final filteredProducts = widget.products.where((p) {
      if (_selectedCategory != null) {
        return (p.category ?? 'Uncategorized') == _selectedCategory;
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
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textPrimary, size: 20),
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
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppTheme.textPrimary),
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
              style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search products by name or code...',
                hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textMuted, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, color: AppTheme.textMuted, size: 20),
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                            _searchController.clear();
                          });
                        },
                      )
                    : null,
                fillColor: Colors.white,
                filled: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                  borderSide: const BorderSide(color: AppTheme.primary, width: 2),
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
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.15,
                      ),
                      itemCount: categoryList.length,
                      itemBuilder: (context, index) {
                        final cat = categoryList[index];
                        final count = categories[cat] ?? 0;
                        return InkWell(
                          onTap: () => setState(() => _selectedCategory = cat),
                          borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.02),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  '📁',
                                  style: TextStyle(fontSize: 36),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  cat,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: AppTheme.textPrimary,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryLight,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    '$count items',
                                    style: const TextStyle(
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
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inventory_2_outlined, size: 48, color: AppTheme.textMuted),
                              SizedBox(height: 12),
                              Text(
                                'No products found',
                                style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: displayProducts.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final p = displayProducts[index];
                            return InkWell(
                              onTap: () => widget.onSelected(p),
                              borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.01),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            p.code,
                                            style: const TextStyle(
                                              fontFamily: 'monospace',
                                              fontWeight: FontWeight.w900,
                                              fontSize: 13,
                                              color: AppTheme.primary,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            p.name,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.textSecondary,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryLight,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Qty: ${p.quantity}',
                                        style: const TextStyle(
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
