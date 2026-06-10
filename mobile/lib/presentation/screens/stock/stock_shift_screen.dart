import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/product.dart';
import '../../providers/api_client_provider.dart';
import '../../providers/products_provider.dart';
import '../../providers/warehouse_stock_summary_provider.dart';
import '../../providers/warehouses_provider.dart';

class StockShiftScreen extends ConsumerStatefulWidget {
  final String? productId;

  const StockShiftScreen({super.key, this.productId});

  @override
  ConsumerState<StockShiftScreen> createState() => _StockShiftScreenState();
}

class _StockShiftScreenState extends ConsumerState<StockShiftScreen> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _notesController = TextEditingController();

  String? _productId;
  String _colorName = 'Default';
  String? _fromWarehouseId;
  String? _toWarehouseId;
  bool _loadingDistribution = false;
  bool _submitting = false;
  List<Map<String, dynamic>> _distribution = const [];

  @override
  void initState() {
    super.initState();
    _productId = widget.productId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final productId = _productId;
      if (productId != null && productId.isNotEmpty) {
        _loadDistribution(productId);
      }
    });
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadDistribution(String productId) async {
    setState(() {
      _loadingDistribution = true;
      _distribution = const [];
    });
    try {
      final client = ref.read(apiClientProvider);
      final res = await client.get(
        '/products/${Uri.encodeQueryComponent(productId)}/stock-distribution',
      );
      final rows = ((res is Map ? res['data'] : null) as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      if (!mounted) return;
      setState(() {
        _distribution = rows;
        final firstStockRow = rows.firstWhere(
          (row) => _safeInt(row['quantity']) > 0,
          orElse: () => <String, dynamic>{},
        );
        if (firstStockRow.isNotEmpty) {
          _colorName =
              (firstStockRow['color_name']?.toString() ?? 'Default').trim();
          _fromWarehouseId = firstStockRow['warehouse_id']?.toString();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _distribution = const [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load warehouse stock: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingDistribution = false;
        });
      }
    }
  }

  int _safeInt(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  List<Map<String, dynamic>> get _colorRows {
    final byColor = <String, Map<String, dynamic>>{};
    for (final row in _distribution) {
      final color = (row['color_name']?.toString() ?? '').trim();
      if (color.isEmpty) continue;
      final qty = _safeInt(row['quantity']);
      if (qty <= 0) continue;
      final key = color.toLowerCase();
      final existing = byColor[key];
      if (existing == null) {
        byColor[key] = {'color_name': color, 'available_quantity': qty};
      } else {
        existing['available_quantity'] =
            _safeInt(existing['available_quantity']) + qty;
      }
    }
    final rows = byColor.values.toList();
    rows.sort((a, b) => a['color_name']
        .toString()
        .toLowerCase()
        .compareTo(b['color_name'].toString().toLowerCase()));
    return rows;
  }

  Set<String> get _sourceWarehouseIds {
    final colorLc = _colorName.trim().toLowerCase();
    return _distribution
        .where((row) =>
            (row['color_name']?.toString() ?? '').trim().toLowerCase() ==
                colorLc &&
            _safeInt(row['quantity']) > 0)
        .map((row) => row['warehouse_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  int get _availableQty {
    final colorLc = _colorName.trim().toLowerCase();
    final row = _distribution.firstWhere(
      (entry) =>
          entry['warehouse_id']?.toString() == _fromWarehouseId &&
          (entry['color_name']?.toString() ?? '').trim().toLowerCase() ==
              colorLc,
      orElse: () => <String, dynamic>{},
    );
    return _safeInt(row['quantity']);
  }

  void _onColorChanged(String color, List<Map<String, dynamic>> warehouses) {
    final colorLc = color.trim().toLowerCase();
    final firstSource = _distribution.firstWhere(
      (row) =>
          (row['color_name']?.toString() ?? '').trim().toLowerCase() ==
              colorLc &&
          _safeInt(row['quantity']) > 0,
      orElse: () => <String, dynamic>{},
    );
    final nextFrom = firstSource['warehouse_id']?.toString();
    setState(() {
      _colorName = color;
      _fromWarehouseId = nextFrom;
      if (_toWarehouseId == null || _toWarehouseId == nextFrom) {
        _toWarehouseId = warehouses
            .map((w) => w['id']?.toString() ?? '')
            .firstWhere((id) => id.isNotEmpty && id != nextFrom,
                orElse: () => '');
        if (_toWarehouseId == '') _toWarehouseId = null;
      }
      _quantityController.clear();
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final productId = _productId;
    if (productId == null || productId.isEmpty) return;
    final qty = int.tryParse(_quantityController.text.trim()) ?? 0;
    if (qty > _availableQty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Only $_availableQty pcs available in source warehouse.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    setState(() {
      _submitting = true;
    });
    try {
      final client = ref.read(apiClientProvider);
      await client.post('/transactions/shift', {
        'product_id': productId,
        'color_name': _colorName,
        'from_warehouse_id': _fromWarehouseId,
        'to_warehouse_id': _toWarehouseId,
        'quantity': qty,
        'notes': _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      });
      ref.invalidate(productsProvider);
      ref.invalidate(activeWarehousesProvider);
      ref.invalidate(warehouseStockSummaryProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stock shifted successfully'),
          backgroundColor: AppTheme.success,
        ),
      );
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to shift stock: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);
    final warehousesAsync = ref.watch(activeWarehousesProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor(context),
      appBar: AppBar(
        title: const Text('Shift Stock'),
        backgroundColor: AppTheme.surfaceColor(context),
        foregroundColor: AppTheme.primaryTextColor(context),
      ),
      body: productsAsync.when(
        data: (products) => warehousesAsync.when(
          data: (warehouses) => _buildForm(products, warehouses),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('Warehouses failed: $error')),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Products failed: $error')),
      ),
    );
  }

  Widget _buildForm(List<Product> products, List<Map<String, dynamic>> warehouses) {
    final selectedProduct = _productId == null
        ? null
        : products.where((p) => p.id == _productId).firstOrNull;
    final sourceIds = _sourceWarehouseIds;
    final sourceWarehouses = warehouses
        .where((warehouse) => sourceIds.contains(warehouse['id']?.toString()))
        .toList();
    final destinationWarehouses = warehouses
        .where((warehouse) => warehouse['id']?.toString() != _fromWarehouseId)
        .toList();

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey('shift-product-$_productId'),
            initialValue: _productId != null && products.any((p) => p.id == _productId)
                ? _productId
                : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Product'),
            items: products
                .map(
                  (product) => DropdownMenuItem(
                    value: product.id,
                    child: Text(
                      '${product.code} - ${product.name}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            validator: (value) =>
                value == null || value.isEmpty ? 'Select product' : null,
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _productId = value;
                _fromWarehouseId = null;
                _quantityController.clear();
              });
              _loadDistribution(value);
            },
          ),
          if (selectedProduct != null) ...[
            const SizedBox(height: 12),
            _InfoPanel(
              title: selectedProduct.code,
              subtitle:
                  '${selectedProduct.quantity} total pcs across all warehouses',
            ),
          ],
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey('shift-color-${_productId ?? ''}-$_colorName'),
            initialValue: _colorRows.any((row) => row['color_name'] == _colorName)
                ? _colorName
                : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Color'),
            items: _colorRows
                .map(
                  (row) => DropdownMenuItem(
                    value: row['color_name'].toString(),
                    child: Text(
                      '${row['color_name']} (${row['available_quantity']} pcs)',
                    ),
                  ),
                )
                .toList(),
            validator: (value) =>
                value == null || value.isEmpty ? 'Select color' : null,
            onChanged:
                _loadingDistribution ? null : (value) => _onColorChanged(value!, warehouses),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey('shift-from-${_productId ?? ''}-${_colorName}_$_fromWarehouseId'),
            initialValue: _fromWarehouseId != null &&
                    sourceWarehouses.any((w) => w['id']?.toString() == _fromWarehouseId)
                ? _fromWarehouseId
                : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'From warehouse'),
            items: sourceWarehouses
                .map(
                  (warehouse) => DropdownMenuItem(
                    value: warehouse['id']?.toString() ?? '',
                    child: Text(warehouse['name']?.toString() ?? 'Warehouse'),
                  ),
                )
                .toList(),
            validator: (value) =>
                value == null || value.isEmpty ? 'Select source warehouse' : null,
            onChanged: (value) {
              setState(() {
                _fromWarehouseId = value;
                if (_toWarehouseId == value) {
                  _toWarehouseId = destinationWarehouses
                      .map((w) => w['id']?.toString() ?? '')
                      .firstWhere((id) => id.isNotEmpty && id != value,
                          orElse: () => '');
                  if (_toWarehouseId == '') _toWarehouseId = null;
                }
                _quantityController.clear();
              });
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey('shift-to-${_fromWarehouseId ?? ''}-${_toWarehouseId ?? ''}'),
            initialValue: _toWarehouseId != null &&
                    destinationWarehouses.any((w) => w['id']?.toString() == _toWarehouseId)
                ? _toWarehouseId
                : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'To warehouse'),
            items: destinationWarehouses
                .map(
                  (warehouse) => DropdownMenuItem(
                    value: warehouse['id']?.toString() ?? '',
                    child: Text(warehouse['name']?.toString() ?? 'Warehouse'),
                  ),
                )
                .toList(),
            validator: (value) => value == null || value.isEmpty
                ? 'Select destination warehouse'
                : null,
            onChanged: (value) => setState(() => _toWarehouseId = value),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _quantityController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Quantity',
              helperText: 'Available in source: $_availableQty pcs',
            ),
            validator: (value) {
              final qty = int.tryParse(value?.trim() ?? '') ?? 0;
              if (qty <= 0) return 'Enter quantity';
              if (qty > _availableQty) return 'Only $_availableQty pcs available';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _notesController,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.swap_horiz_rounded),
            label: Text(_submitting ? 'Shifting...' : 'Shift Stock'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  final String title;
  final String subtitle;

  const _InfoPanel({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight,
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppTheme.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              color: AppTheme.secondaryTextColor(context),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
