import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../providers/products_provider.dart';
import '../../providers/api_client_provider.dart';
import '../../providers/warehouses_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/transactions_provider.dart';
import '../../providers/warehouse_stock_summary_provider.dart';
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
  final String? transactionId;
  final String? createdAt;
  final String? workerId;
  final bool initialShift;

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
    this.transactionId,
    this.createdAt,
    this.workerId,
    this.initialShift = false,
  });

  @override
  ConsumerState<StockEntryScreen> createState() => _StockEntryScreenState();
}

class _StockEntryScreenState extends ConsumerState<StockEntryScreen> {
  static const String _stockEntryPrefsKey = 'stock_entry_prefs_v2';
  final _formKey = GlobalKey<FormState>();
  final _qtyController = TextEditingController();
  final _cartonsController = TextEditingController();
  final _pcsPerCartonController = TextEditingController();
  final _notesController = TextEditingController();
  final _recordedByController = TextEditingController();
  final _customerController = TextEditingController();

  bool get _isEditing => widget.transactionId != null;

  bool get _isEditingOlderThan12Hours {
    if (!_isEditing || widget.createdAt == null) return false;
    final parsed = DateTime.tryParse(widget.createdAt!);
    if (parsed == null) return false;
    return DateTime.now().difference(parsed).inHours > 12;
  }

  String _getCleanNotes(String? notes) {
    if (notes == null) return '';
    var clean = notes.trim();
    clean = clean
        .replaceFirst(
            RegExp(r'^Customer:\s*[^|]+(\|)?', caseSensitive: false), '')
        .trim();
    clean = clean
        .replaceFirst(
            RegExp(
                r'^\d+\s*(?:ctn|carton|cartons)\s*(?:[x*]|\(|pcs\/ctn|pcs)?\s*\d+\s*(?:pcs)?\s*(\|)?',
                caseSensitive: false),
            '')
        .trim();
    return clean;
  }

  Product? _selectedProduct;
  String _selectedColor = 'Default';
  TransactionType _type = TransactionType.stockIn;
  String? _selectedWarehouseId;
  String? _toWarehouseId;
  bool _isShift = false;
  Set<String> _stockOutWarehouseIdsWithStock = <String>{};
  List<Map<String, dynamic>> _stockOutWarehouseStockRows = const [];
  List<Map<String, dynamic>> _stockOutColorRows = const [];
  bool _isLoadingStockOutWarehouses = false;
  bool _isSubmitting = false;
  // Global "last used" warehouse preferences (not per-product). Remembers the
  // warehouse a worker last used so repeated entries pre-select it.
  String? _prefInWarehouseId; // last warehouse used for Stock In
  String? _prefShiftFromId; // last source warehouse used for Shift
  String? _prefShiftToId; // last destination warehouse used for Shift
  final Set<String> _prefetchedProductImageUrls = <String>{};

  // Optimization: client-side stock distribution cache
  List<Map<String, dynamic>> _productStockDistribution = const [];
  String? _lastLoadedProductId;

  bool get _usesSourceStock => _type == TransactionType.stockOut || _isShift;

  @override
  void initState() {
    super.initState();
    if (widget.initialType != null) _type = widget.initialType!;
    if (widget.initialShift) {
      _isShift = true;
      _type = TransactionType.stockOut;
    }
    _loadStockEntryPrefs();

    // Auto-select product if ID is provided
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentUser = ref.read(currentUserProvider);
      setState(() {
        _recordedByController.text =
            widget.initialRecordedBy ?? currentUser?.name ?? 'Ashish';
        if (widget.initialNotes != null) {
          _notesController.text = _getCleanNotes(widget.initialNotes!);
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
          _refreshStockOutWarehouses(
              autoRouteWarehouse: true, autoRouteColor: true);
        }
      }
    });

    _cartonsController.addListener(_calculateTotal);
    _pcsPerCartonController.addListener(_calculateTotal);
  }

  String? _normalizePrefId(dynamic value) {
    final id = (value?.toString() ?? '').trim();
    return id.isEmpty ? null : id;
  }

  Future<void> _loadStockEntryPrefs() async {
    try {
      final box = Hive.box(AppConstants.settingsBox);
      final raw = box.get(_stockEntryPrefsKey);
      if (raw is Map) {
        if (!mounted) return;
        setState(() {
          _prefInWarehouseId = _normalizePrefId(raw['in_warehouse_id']);
          _prefShiftFromId = _normalizePrefId(raw['shift_from_id']);
          _prefShiftToId = _normalizePrefId(raw['shift_to_id']);
        });
      }
    } catch (_) {
      // Keep default behavior if prefs read fails.
    }
  }

  /// Persists the warehouse(s) just used so the next entry pre-selects them.
  /// Global (last-used), not per-product.
  Future<void> _saveStockEntryPrefs() async {
    if (_isEditing) return; // edits shouldn't move the "last used" default

    final next = <String, dynamic>{
      'in_warehouse_id': _prefInWarehouseId,
      'shift_from_id': _prefShiftFromId,
      'shift_to_id': _prefShiftToId,
    };

    if (_isShift) {
      next['shift_from_id'] = _selectedWarehouseId;
      next['shift_to_id'] = _toWarehouseId;
      _prefShiftFromId = _selectedWarehouseId;
      _prefShiftToId = _toWarehouseId;
    } else if (_type == TransactionType.stockIn) {
      next['in_warehouse_id'] = _selectedWarehouseId;
      _prefInWarehouseId = _selectedWarehouseId;
    } else {
      return; // Stock Out keeps auto-routing; nothing to remember.
    }

    try {
      await Hive.box(AppConstants.settingsBox).put(_stockEntryPrefsKey, next);
    } catch (_) {
      // Transaction success should not depend on prefs persistence.
    }
  }

  void _prefetchProductImages(List<Product> products) {
    if (products.isEmpty || !mounted) return;
    final urls = products
        .map((p) {
          if ((p.imageUrl ?? '').trim().isNotEmpty) return p.imageUrl!.trim();
          if (p.images.isNotEmpty && p.images.first.url.trim().isNotEmpty) {
            return p.images.first.url.trim();
          }
          return '';
        })
        .where((url) => url.isNotEmpty)
        .take(36);

    for (final url in urls) {
      if (_prefetchedProductImageUrls.contains(url)) continue;
      _prefetchedProductImageUrls.add(url);
      precacheImage(
        NetworkImage(url),
        context,
        onError: (exception, stackTrace) {
          // Suppress prefetching exceptions for broken URLs or network interruptions.
        },
      );
    }
  }

  void _calculateTotal() {
    if (_isEditingOlderThan12Hours) return;
    final cartons = int.tryParse(_cartonsController.text) ?? 0;
    final pcs = int.tryParse(_pcsPerCartonController.text) ?? 0;
    if (cartons > 0 && pcs > 0) {
      setState(() {
        _qtyController.text = (cartons * pcs).toString();
      });
    }
  }

  String _normalizedCategory(String category) {
    final trimmed = category.trim();
    return trimmed.isEmpty ? 'uncategorized' : trimmed.toLowerCase();
  }

  Product? _originalTransactionProduct(List<Product> products) {
    final originalProductId = widget.productId;
    if (originalProductId == null || originalProductId.isEmpty) return null;
    return products.where((p) => p.id == originalProductId).firstOrNull;
  }

  List<Product>? _productsForPicker(List<Product> products) {
    if (_isEditing) {
      final original = _originalTransactionProduct(products);
      if (original == null) return null;

      final originalCategory = _normalizedCategory(original.category);
      return products
          .where((p) => _normalizedCategory(p.category) == originalCategory)
          .toList();
    }

    if (_usesSourceStock) {
      return products.where((p) => p.quantity > 0).toList();
    }

    return products;
  }

  String? _editingCategoryLabel(List<Product> products) {
    if (!_isEditing) return null;
    final original = _originalTransactionProduct(products);
    final raw = original?.category.trim();
    if (raw == null || raw.isEmpty) return 'Uncategorized';
    return raw;
  }

  Future<void> _loadProductStockDistribution({
    bool autoRouteWarehouse = false,
    bool autoRouteColor = false,
  }) async {
    final product = _selectedProduct;
    if (product == null) {
      setState(() {
        _productStockDistribution = const [];
        _stockOutWarehouseStockRows = const [];
        _stockOutColorRows = const [];
      });
      return;
    }

    setState(() {
      _isLoadingStockOutWarehouses = true;
    });

    try {
      final client = ref.read(apiClientProvider);
      final productId = Uri.encodeQueryComponent(product.id);
      final response =
          await client.get('/products/$productId/stock-distribution');
      final list =
          (response is Map ? response['data'] : null) as List? ?? const [];
      final rows = list
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      if (!mounted) return;
      setState(() {
        _productStockDistribution = rows;
      });

      // For stock-out, automatically select the first color that has stock
      if (_usesSourceStock && rows.isNotEmpty) {
        final currentColor = _selectedColor.trim().toLowerCase();
        final currentHasStock = rows.any((r) =>
            (r['color_name']?.toString() ?? '').trim().toLowerCase() ==
                currentColor &&
            (int.tryParse(r['quantity']?.toString() ?? '0') ?? 0) > 0);

        if (!currentHasStock) {
          final stockRow = rows.firstWhere(
            (r) => (int.tryParse(r['quantity']?.toString() ?? '0') ?? 0) > 0,
            orElse: () => <String, dynamic>{},
          );
          if (stockRow.isNotEmpty) {
            final color = stockRow['color_name']?.toString() ?? 'Default';
            setState(() {
              _selectedColor = color;
            });
          }
        }
      }

      _applyInMemoryFilters(
        autoRouteWarehouse: autoRouteWarehouse,
        autoRouteColor: autoRouteColor,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _productStockDistribution = const [];
      });
      _applyInMemoryFilters(
        autoRouteWarehouse: autoRouteWarehouse,
        autoRouteColor: autoRouteColor,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingStockOutWarehouses = false;
        });
      }
    }
  }

  void _applyInMemoryFilters({
    bool autoRouteWarehouse = false,
    bool autoRouteColor = false,
  }) {
    if (!_usesSourceStock || _selectedProduct == null) {
      setState(() {
        _stockOutWarehouseIdsWithStock = <String>{};
        _stockOutWarehouseStockRows = const [];
        _stockOutColorRows = const [];
      });
      return;
    }

    final targetColor = _selectedColor.trim().toLowerCase();

    // 1. Group stocks by warehouse (filtered by selected color for the dashboard/warning state)
    final warehouseQtyMap = <String, int>{};
    final warehouseDetailMap = <String, Map<String, dynamic>>{};

    for (final row in _productStockDistribution) {
      final wid = row['warehouse_id']?.toString() ?? '';
      if (wid.isEmpty) continue;

      final rowColor =
          (row['color_name']?.toString() ?? '').trim().toLowerCase();

      if (targetColor.isNotEmpty &&
          targetColor != 'default' &&
          rowColor != targetColor) {
        continue;
      }

      final qty = int.tryParse(row['quantity']?.toString() ?? '0') ?? 0;
      if (qty <= 0) continue;

      warehouseQtyMap[wid] = (warehouseQtyMap[wid] ?? 0) + qty;
      warehouseDetailMap[wid] = row;
    }

    final warehouseRows = warehouseQtyMap.entries.map((e) {
      final detail = warehouseDetailMap[e.key]!;
      return {
        'warehouse_id': e.key,
        'warehouse_name': detail['warehouse_name'] ?? 'Warehouse',
        'location': detail['location'] ?? '',
        'available_quantity': e.value,
      };
    }).toList();

    warehouseRows.sort((a, b) => (b['available_quantity'] as int)
        .compareTo(a['available_quantity'] as int));

    // Calculate all warehouses where the product has any stock (unfiltered for dropdown free selection)
    final allWarehouseIdsWithStock = _productStockDistribution
        .map((r) => r['warehouse_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    // 2. Group available colors (unfiltered by warehouse for dropdown free selection)
    final colorQtyMap = <String, int>{};
    final colorNameMap = <String, String>{};

    for (final row in _productStockDistribution) {
      final colorName = (row['color_name']?.toString() ?? '').trim();
      if (colorName.isEmpty) continue;

      final key = colorName.toLowerCase();
      final qty = int.tryParse(row['quantity']?.toString() ?? '0') ?? 0;
      if (qty <= 0) continue;

      colorQtyMap[key] = (colorQtyMap[key] ?? 0) + qty;
      colorNameMap[key] = colorName;
    }

    final colorRows = colorQtyMap.entries.map((e) {
      return {
        'color_name': colorNameMap[e.key] ?? e.key,
        'available_quantity': e.value,
      };
    }).toList();

    colorRows.sort((a, b) => (a['color_name'] as String)
        .toLowerCase()
        .compareTo((b['color_name'] as String).toLowerCase()));

    setState(() {
      _stockOutWarehouseStockRows =
          warehouseRows; // Filtered by color for dashboard
      _stockOutWarehouseIdsWithStock =
          allWarehouseIdsWithStock; // All stocked warehouses for dropdown
      _stockOutColorRows =
          colorRows; // All stocked colors for dropdown (free selection)

      // If the currently selected warehouse has no stock for this color, auto-switch to one that does
      final targetColorWarehouseIds = warehouseRows
          .where((r) => (r['available_quantity'] as int) > 0)
          .map((r) => r['warehouse_id'].toString())
          .toSet();

      if (autoRouteWarehouse) {
        if (_selectedWarehouseId != null &&
            !targetColorWarehouseIds.contains(_selectedWarehouseId)) {
          if (targetColorWarehouseIds.isNotEmpty) {
            _selectedWarehouseId =
                warehouseRows.first['warehouse_id']?.toString();
          }
        }
      }

      if (_selectedWarehouseId == null && allWarehouseIdsWithStock.isNotEmpty) {
        final preferredWarehouse = warehouseRows.isNotEmpty
            ? warehouseRows.first['warehouse_id']?.toString()
            : allWarehouseIdsWithStock.first;
        _selectedWarehouseId = preferredWarehouse;
      }

      // If autoRouteColor is true, auto-switch to a color that has stock in the selected warehouse
      if (autoRouteColor && _selectedWarehouseId != null) {
        final colorsInSelectedWarehouse = _productStockDistribution
            .where((r) {
              final wid = r['warehouse_id']?.toString() ?? '';
              final qty = int.tryParse(r['quantity']?.toString() ?? '0') ?? 0;
              return wid == _selectedWarehouseId && qty > 0;
            })
            .map(
                (r) => (r['color_name']?.toString() ?? '').trim().toLowerCase())
            .toSet();

        final currentColor = _selectedColor.trim().toLowerCase();
        if (!colorsInSelectedWarehouse.contains(currentColor) &&
            colorsInSelectedWarehouse.isNotEmpty) {
          final firstStockedColor = _productStockDistribution.firstWhere(
            (r) {
              final wid = r['warehouse_id']?.toString() ?? '';
              final qty = int.tryParse(r['quantity']?.toString() ?? '0') ?? 0;
              return wid == _selectedWarehouseId && qty > 0;
            },
            orElse: () => <String, dynamic>{},
          );
          if (firstStockedColor.isNotEmpty) {
            _selectedColor =
                firstStockedColor['color_name']?.toString() ?? 'Default';
          }
        }
      }

      final availableColorNames = colorRows
          .map((r) => r['color_name'].toString().trim().toLowerCase())
          .toSet();
      if (_selectedColor.trim().isNotEmpty &&
          !availableColorNames.contains(_selectedColor.trim().toLowerCase())) {
        _selectedColor = colorRows.isNotEmpty
            ? (colorRows.first['color_name']?.toString() ?? 'Default')
            : 'Default';
      }
    });
  }

  Future<void> _refreshStockOutWarehouses({
    bool autoRouteWarehouse = false,
    bool autoRouteColor = false,
  }) async {
    if (!_usesSourceStock || _selectedProduct == null) {
      setState(() {
        _stockOutWarehouseIdsWithStock = <String>{};
        _stockOutWarehouseStockRows = const [];
        _stockOutColorRows = const [];
        _isLoadingStockOutWarehouses = false;
      });
      return;
    }

    if (_lastLoadedProductId != _selectedProduct!.id) {
      _lastLoadedProductId = _selectedProduct!.id;
      await _loadProductStockDistribution(
        autoRouteWarehouse: autoRouteWarehouse,
        autoRouteColor: autoRouteColor,
      );
    } else {
      _applyInMemoryFilters(
        autoRouteWarehouse: autoRouteWarehouse,
        autoRouteColor: autoRouteColor,
      );
    }
  }

  Future<void> _refreshStockOutColors({
    bool autoRouteWarehouse = false,
    bool autoRouteColor = false,
  }) async {
    if (!_usesSourceStock || _selectedProduct == null) {
      setState(() {
        _stockOutColorRows = const [];
      });
      return;
    }

    if (_lastLoadedProductId != _selectedProduct!.id) {
      _lastLoadedProductId = _selectedProduct!.id;
      await _loadProductStockDistribution(
        autoRouteWarehouse: autoRouteWarehouse,
        autoRouteColor: autoRouteColor,
      );
    } else {
      _applyInMemoryFilters(
        autoRouteWarehouse: autoRouteWarehouse,
        autoRouteColor: autoRouteColor,
      );
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

  int get _selectedSourceAvailableQty {
    if (!_usesSourceStock ||
        _selectedWarehouseId == null ||
        _selectedWarehouseId!.trim().isEmpty) {
      return 0;
    }

    final targetColor = _selectedColor.trim().toLowerCase();
    var total = 0;
    for (final row in _productStockDistribution) {
      final warehouseId = row['warehouse_id']?.toString() ?? '';
      final colorName =
          (row['color_name']?.toString() ?? '').trim().toLowerCase();
      if (warehouseId == _selectedWarehouseId && colorName == targetColor) {
        total += int.tryParse(row['quantity']?.toString() ?? '0') ?? 0;
      }
    }
    return total;
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

    if (!_isEditingOlderThan12Hours &&
        (_selectedWarehouseId == null ||
            _selectedWarehouseId!.trim().isEmpty ||
            _selectedWarehouseId == 'default')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a warehouse.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }
    if (!_isEditingOlderThan12Hours) {
      final activeWarehouses = ref.read(activeWarehousesProvider).value ?? [];
      final selectedWarehouseExists = activeWarehouses.any(
        (w) => w['id']?.toString() == _selectedWarehouseId,
      );
      if (!selectedWarehouseExists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Please select an active warehouse from the server list.'),
            backgroundColor: AppTheme.danger,
          ),
        );
        return;
      }
      if (_isShift) {
        final destinationWarehouseExists = activeWarehouses.any(
          (w) => w['id']?.toString() == _toWarehouseId,
        );
        if (_toWarehouseId == null || _toWarehouseId!.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please select a destination warehouse.'),
              backgroundColor: AppTheme.danger,
            ),
          );
          return;
        }
        if (_selectedWarehouseId == _toWarehouseId) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Source and destination warehouses must be different.'),
              backgroundColor: AppTheme.danger,
            ),
          );
          return;
        }
        if (!destinationWarehouseExists) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Please select an active destination warehouse from the server list.'),
              backgroundColor: AppTheme.danger,
            ),
          );
          return;
        }
      }
    }

    // Validation for movements that remove stock from a source warehouse.
    if (_usesSourceStock && !_isEditingOlderThan12Hours) {
      if (_selectedWarehouseId == null ||
          _selectedWarehouseId!.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isShift
                ? 'Please select a source warehouse for Shift.'
                : 'Please select a warehouse for Stock Out.'),
            backgroundColor: AppTheme.danger,
          ),
        );
        return;
      }

      int availableQty = _selectedSourceAvailableQty;

      // Adjust for virtual quantity during editing
      if (_isEditing && widget.productId == _selectedProduct!.id) {
        final oldQty = widget.initialQuantity ?? 0;
        final oldType = widget.initialType;
        final oldColor = widget.initialColorName ?? 'Default';

        if (oldType == TransactionType.stockOut) {
          if (oldColor.trim().toLowerCase() ==
              _selectedColor.trim().toLowerCase()) {
            availableQty += oldQty;
          }
        } else if (oldType == TransactionType.stockIn) {
          if (oldColor.trim().toLowerCase() ==
              _selectedColor.trim().toLowerCase()) {
            availableQty -= oldQty;
          }
        }
      }

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

      if (_isEditing) {
        await client.patch('/transactions/${widget.transactionId}', {
          'product_id': _selectedProduct!.id,
          'type': _type == TransactionType.stockIn ? 'stock_in' : 'stock_out',
          'quantity': qty,
          'color_name': _selectedColor,
          'warehouse_id': _selectedWarehouseId,
          'notes': finalNotes.isEmpty ? null : finalNotes,
          'worker_name': workerName,
          'cartons': cartonsText.isNotEmpty ? int.tryParse(cartonsText) : null,
          'pcs_per_carton': resolvedPcsPerCarton,
        });
      } else if (_isShift) {
        await client.post('/transactions/shift', {
          'product_id': _selectedProduct!.id,
          'quantity': qty,
          'color_name': _selectedColor,
          'from_warehouse_id': _selectedWarehouseId,
          'to_warehouse_id': _toWarehouseId,
          'notes': finalNotes.isEmpty ? null : finalNotes,
          'worker_name': workerName,
        });
      } else {
        await client.post('/transactions', {
          'product_id': _selectedProduct!.id,
          'product_name': _selectedProduct!.name,
          'type': _type == TransactionType.stockIn ? 'stock_in' : 'stock_out',
          'quantity': qty,
          'color_name': _selectedColor,
          'notes': finalNotes,
          'warehouse_id': (_selectedWarehouseId == null ||
                  _selectedWarehouseId == 'default')
              ? null
              : _selectedWarehouseId,
          'worker_name': workerName,
          if (cartonsText.isNotEmpty) 'cartons': int.tryParse(cartonsText),
          'pcs_per_carton': resolvedPcsPerCarton,
        });
      }
      await _saveStockEntryPrefs();
      try {
        await Future.wait([
          ref.read(productsProvider.notifier).fetchProducts(),
          ref.read(transactionsProvider.notifier).fetchTransactions(),
        ]);
        ref.invalidate(activeWarehousesProvider);
        ref.invalidate(warehouseStockSummaryProvider);
        if (_isEditing) {
          final originalProductId = widget.productId;
          if (originalProductId != null && originalProductId.isNotEmpty) {
            ref.invalidate(productTransactionsProvider(originalProductId));
          }
          ref.invalidate(productTransactionsProvider(_selectedProduct!.id));
        }
      } catch (_) {
        // Realtime subscriptions normally refresh this too; do not fail a saved edit.
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isShift
                ? 'Stock shifted successfully'
                : 'Transaction saved successfully'),
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

  void _openProductPicker(
    List<Product> products, {
    bool correctionMode = false,
    String? helperText,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ProductPickerModal(
        products: products,
        initialShowProductsDirectly: correctionMode,
        helperText: helperText,
        onSelected: (p) {
          final defaultPcsPerCarton =
              (p.pcsPerCarton != null && p.pcsPerCarton! > 0)
                  ? p.pcsPerCarton!
                  : 1;
          setState(() {
            _selectedProduct = p;
            if (p.colorStocks.isNotEmpty) {
              final preferredColor =
                  (correctionMode && p.id == widget.productId)
                      ? widget.initialColorName?.trim()
                      : null;
              final hasPreferredColor = preferredColor != null &&
                  preferredColor.isNotEmpty &&
                  p.colorStocks.any((c) =>
                      c.color.trim().toLowerCase() ==
                      preferredColor.toLowerCase());
              _selectedColor = hasPreferredColor
                  ? preferredColor
                  : p.colorStocks.first.color;
            } else {
              _selectedColor = 'Default';
            }
            _pcsPerCartonController.text = defaultPcsPerCarton.toString();
          });
          _refreshStockOutWarehouses(
              autoRouteWarehouse: true, autoRouteColor: true);
          _refreshStockOutColors(
              autoRouteWarehouse: true, autoRouteColor: true);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<Map<String, dynamic>>>>(
      activeWarehousesProvider,
      (previous, next) {
        if (next.hasValue && _selectedWarehouseId == null) {
          final list = next.value ?? [];
          final active = list.where((w) => w['is_active'] == true).toList();
          if (active.isNotEmpty) {
            final activeIds =
                active.map((w) => w['id']?.toString()).toSet();
            // Validate a remembered id against the live active list before use.
            String? remembered(String? id) =>
                (id != null && activeIds.contains(id)) ? id : null;
            setState(() {
              // Pre-select the worker's last-used warehouse when valid;
              // otherwise fall back to the first active warehouse. Stock Out
              // keeps auto-routing, so only seed In / Shift source here.
              _selectedWarehouseId = (_isShift
                      ? remembered(_prefShiftFromId)
                      : (_type == TransactionType.stockIn
                          ? remembered(_prefInWarehouseId)
                          : null)) ??
                  active.first['id']?.toString();
              final rememberedTo = remembered(_prefShiftToId);
              _toWarehouseId ??= (_isShift &&
                      rememberedTo != null &&
                      rememberedTo != _selectedWarehouseId)
                  ? rememberedTo
                  : active
                      .firstWhere(
                        (w) => w['id']?.toString() != _selectedWarehouseId,
                        orElse: () => const <String, dynamic>{},
                      )['id']
                      ?.toString();
            });
          }
        }
      },
    );

    final products = ref.watch(productsProvider).value ?? [];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prefetchProductImages(products);
    });
    final warehousesAsync = ref.watch(activeWarehousesProvider);
    final warehouses = warehousesAsync.value ?? [];
    final warehouseOptionsRaw = (_usesSourceStock &&
            _selectedProduct != null &&
            !_isLoadingStockOutWarehouses)
        ? warehouses
            .where((w) => _stockOutWarehouseIdsWithStock
                .contains(w['id']?.toString() ?? ''))
            .toList()
        : warehouses;
    final seenWarehouseIds = <String>{};
    final warehouseOptions = warehouseOptionsRaw.where((w) {
      final id = w['id']?.toString() ?? '';
      if (id.isEmpty || seenWarehouseIds.contains(id)) return false;
      seenWarehouseIds.add(id);
      return true;
    }).toList();
    final warehouseOptionIds = warehouseOptions
        .map((w) => w['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final selectedWarehouseValue = (_selectedWarehouseId != null &&
            warehouseOptionIds.contains(_selectedWarehouseId))
        ? _selectedWarehouseId
        : null;
    final destinationWarehouseOptions = warehouses
        .where((w) => (w['id']?.toString() ?? '') != _selectedWarehouseId)
        .toList();
    final destinationWarehouseIds = destinationWarehouseOptions
        .map((w) => w['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final selectedDestinationValue = (_toWarehouseId != null &&
            destinationWarehouseIds.contains(_toWarehouseId))
        ? _toWarehouseId
        : null;
    final stockOutColorRowsDeduped = (() {
      final byLower = <String, Map<String, dynamic>>{};
      for (final row in _stockOutColorRows) {
        final name = (row['color_name']?.toString() ?? '').trim();
        if (name.isEmpty) continue;
        final key = name.toLowerCase();
        final qty = int.tryParse('${row['available_quantity'] ?? 0}') ?? 0;
        if (!byLower.containsKey(key)) {
          byLower[key] = {
            'color_name': name,
            'available_quantity': qty,
          };
        } else {
          final prevQty =
              int.tryParse('${byLower[key]!['available_quantity'] ?? 0}') ?? 0;
          byLower[key]!['available_quantity'] = prevQty + qty;
        }
      }
      final list = byLower.values.toList();
      list.sort((a, b) => (a['color_name']?.toString() ?? '')
          .toLowerCase()
          .compareTo((b['color_name']?.toString() ?? '').toLowerCase()));
      return list;
    })();
    final stockOutColorNames = stockOutColorRowsDeduped
        .map((c) => (c['color_name']?.toString() ?? '').trim())
        .where((x) => x.isNotEmpty)
        .toSet();
    final selectedColorValue = (() {
      if (_usesSourceStock) {
        if (stockOutColorNames.contains(_selectedColor)) return _selectedColor;
        if (stockOutColorRowsDeduped.isNotEmpty) {
          return stockOutColorRowsDeduped.first['color_name']?.toString() ??
              'Default';
        }
        return 'Default';
      }
      final productColorNames = (_selectedProduct?.colorStocks ?? const [])
          .map((c) => c.color)
          .where((x) => x.trim().isNotEmpty)
          .toSet();
      if (productColorNames.contains(_selectedColor)) return _selectedColor;
      if ((_selectedProduct?.colorStocks ?? const []).isNotEmpty) {
        return _selectedProduct!.colorStocks.first.color;
      }
      return 'Default';
    })();

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
              if (_isEditingOlderThan12Hours) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: Colors.amber.shade800, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'This transaction was recorded more than 12 hours ago. Only the customer name and notes can be edited.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // MOVEMENT TYPE
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
                      onTap: _isEditingOlderThan12Hours
                          ? null
                          : () {
                              setState(() {
                                _type = TransactionType.stockIn;
                                _isShift = false;
                              });
                              _refreshStockOutWarehouses(
                                  autoRouteWarehouse: true,
                                  autoRouteColor: true);
                              _refreshStockOutColors(
                                  autoRouteWarehouse: true,
                                  autoRouteColor: true);
                            },
                      child: Opacity(
                        opacity: _isEditingOlderThan12Hours &&
                                _type != TransactionType.stockIn
                            ? 0.4
                            : 1.0,
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
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: _isEditingOlderThan12Hours
                          ? null
                          : () {
                              setState(() {
                                _type = TransactionType.stockOut;
                                _isShift = false;
                                if (!_isEditing &&
                                    _selectedProduct != null &&
                                    _selectedProduct!.quantity <= 0) {
                                  _selectedProduct = null;
                                  _selectedColor = 'Default';
                                }
                              });
                              _refreshStockOutWarehouses(
                                  autoRouteWarehouse: true,
                                  autoRouteColor: true);
                              _refreshStockOutColors(
                                  autoRouteWarehouse: true,
                                  autoRouteColor: true);
                            },
                      child: Opacity(
                        opacity: _isEditingOlderThan12Hours &&
                                (!_usesSourceStock || _isShift)
                            ? 0.4
                            : 1.0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color:
                                _type == TransactionType.stockOut && !_isShift
                                    ? const Color(0xFFFEF2F2)
                                    : Colors.white,
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusLG),
                            border: Border.all(
                              color:
                                  _type == TransactionType.stockOut && !_isShift
                                      ? AppTheme.danger
                                      : const Color(0xFFE2E8F0),
                              width:
                                  _type == TransactionType.stockOut && !_isShift
                                      ? 2
                                      : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.arrow_downward_rounded,
                                size: 16,
                                color: _type == TransactionType.stockOut &&
                                        !_isShift
                                    ? AppTheme.danger
                                    : AppTheme.textMuted,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Stock Out',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: _type == TransactionType.stockOut &&
                                          !_isShift
                                      ? AppTheme.danger
                                      : AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (!_isEditing) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: _isEditingOlderThan12Hours
                            ? null
                            : () {
                                setState(() {
                                  _type = TransactionType.stockOut;
                                  _isShift = true;
                                  // Pre-fill remembered shift warehouses
                                  // (global last-used) when they're still
                                  // active. Source falls back to auto-routing
                                  // if it has no stock for the chosen color.
                                  final activeIds = warehouses
                                      .map((w) => w['id']?.toString())
                                      .toSet();
                                  if (_prefShiftFromId != null &&
                                      activeIds.contains(_prefShiftFromId)) {
                                    _selectedWarehouseId = _prefShiftFromId;
                                  }
                                  if ((_toWarehouseId == null ||
                                          _toWarehouseId ==
                                              _selectedWarehouseId) &&
                                      warehouses.isNotEmpty) {
                                    final rememberedTo = (_prefShiftToId !=
                                                null &&
                                            activeIds.contains(_prefShiftToId) &&
                                            _prefShiftToId !=
                                                _selectedWarehouseId)
                                        ? _prefShiftToId
                                        : null;
                                    _toWarehouseId = rememberedTo ??
                                        warehouses
                                            .firstWhere(
                                              (w) =>
                                                  w['id']?.toString() !=
                                                  _selectedWarehouseId,
                                              orElse: () =>
                                                  const <String, dynamic>{},
                                            )['id']
                                            ?.toString();
                                  }
                                  if (_selectedProduct != null &&
                                      _selectedProduct!.quantity <= 0) {
                                    _selectedProduct = null;
                                    _selectedColor = 'Default';
                                  }
                                });
                                _refreshStockOutWarehouses(
                                    autoRouteWarehouse: true,
                                    autoRouteColor: true);
                                _refreshStockOutColors(
                                    autoRouteWarehouse: true,
                                    autoRouteColor: true);
                              },
                        child: Opacity(
                          opacity: _isEditingOlderThan12Hours && !_isShift
                              ? 0.4
                              : 1.0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: _isShift
                                  ? const Color(0xFFEFF6FF)
                                  : Colors.white,
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusLG),
                              border: Border.all(
                                color: _isShift
                                    ? AppTheme.primary
                                    : const Color(0xFFE2E8F0),
                                width: _isShift ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.swap_horiz_rounded,
                                  size: 16,
                                  color: _isShift
                                      ? AppTheme.primary
                                      : AppTheme.textMuted,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Shift',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: _isShift
                                        ? AppTheme.primary
                                        : AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 24),

              // PRODUCT SELECTION
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
                onTap: _isEditingOlderThan12Hours
                    ? null
                    : () {
                        final pickerProducts = _productsForPicker(products);
                        if (pickerProducts == null || pickerProducts.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Product list is still loading. Please try again.'),
                              backgroundColor: AppTheme.danger,
                            ),
                          );
                          return;
                        }
                        final categoryLabel = _editingCategoryLabel(products);
                        _openProductPicker(
                          pickerProducts,
                          correctionMode: _isEditing,
                          helperText: _isEditing && categoryLabel != null
                              ? 'Edit mode: choose another product only inside "$categoryLabel".'
                              : null,
                        );
                      },
                borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                child: Opacity(
                  opacity: _isEditingOlderThan12Hours ? 0.6 : 1.0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
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
                              ? Text(
                                  _selectedProduct!.code,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                    color: AppTheme.primary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : Text(
                                  'Choose product code...',
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
              ),
              if (_isEditing && !_isEditingOlderThan12Hours) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 15,
                      color: AppTheme.mutedTextColor(context),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Product correction is limited to the original folder/category.',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.mutedTextColor(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),

              // WAREHOUSE & COLOR ROW
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Warehouse Dropdown
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isShift ? 'FROM WAREHOUSE' : 'WAREHOUSE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: AppTheme.mutedTextColor(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        IgnorePointer(
                          ignoring: _isEditingOlderThan12Hours,
                          child: Opacity(
                            opacity: _isEditingOlderThan12Hours ? 0.6 : 1.0,
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceColor(context),
                                borderRadius:
                                    BorderRadius.circular(AppTheme.radiusLG),
                                border: Border.all(
                                    color: AppTheme.borderColor(context)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: selectedWarehouseValue,
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
                                  items: (_usesSourceStock &&
                                          _selectedProduct != null &&
                                          !_isLoadingStockOutWarehouses &&
                                          warehouseOptions.isEmpty)
                                      ? [
                                          DropdownMenuItem(
                                            value: '__no_stock__',
                                            child: Text(
                                              'No warehouse has stock for this color',
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  color:
                                                      AppTheme.primaryTextColor(
                                                          context)),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ]
                                      : warehouses.isEmpty
                                          ? [
                                              DropdownMenuItem(
                                                value: '__none__',
                                                child: Text(
                                                  warehousesAsync.isLoading
                                                      ? 'Loading warehouses...'
                                                      : 'No active warehouses on server',
                                                  style: TextStyle(
                                                      fontSize: 13,
                                                      color: AppTheme
                                                          .primaryTextColor(
                                                              context)),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ]
                                          : warehouseOptions.map((w) {
                                              final name =
                                                  w['name']?.toString() ??
                                                      'Main Warehouse';
                                              final loc =
                                                  w['location']?.toString() ??
                                                      '';
                                              final display = loc.isNotEmpty
                                                  ? '$name - $loc'
                                                  : name;
                                              return DropdownMenuItem(
                                                value: w['id']?.toString(),
                                                child: Text(
                                                  display,
                                                  style: TextStyle(
                                                      fontSize: 13,
                                                      color: AppTheme
                                                          .primaryTextColor(
                                                              context)),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              );
                                            }).toList(),
                                  onChanged: _isEditingOlderThan12Hours
                                      ? null
                                      : (val) {
                                          if (val == null ||
                                              val.startsWith('__')) {
                                            return;
                                          }
                                          setState(() {
                                            _selectedWarehouseId = val;
                                            if (_isShift &&
                                                _toWarehouseId == val) {
                                              _toWarehouseId =
                                                  destinationWarehouseOptions
                                                      .firstWhere(
                                                        (w) =>
                                                            w['id']
                                                                ?.toString() !=
                                                            val,
                                                        orElse: () =>
                                                            const <String,
                                                                dynamic>{},
                                                      )['id']
                                                      ?.toString();
                                            }
                                          });
                                          _refreshStockOutColors(
                                              autoRouteColor: true,
                                              autoRouteWarehouse: false);
                                        },
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (_usesSourceStock) ...[
                          const SizedBox(height: 6),
                          Text(
                            _isLoadingStockOutWarehouses
                                ? 'Checking stock availability...'
                                : 'Only warehouses with available source stock are shown.',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.mutedTextColor(context),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceColor(context),
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusLG),
                              border: Border.all(
                                  color: AppTheme.borderColor(context)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Warehouse Stock Dashboard',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primaryTextColor(context),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (_isLoadingStockOutWarehouses)
                                  Text(
                                    'Loading stock by warehouse...',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.mutedTextColor(context),
                                    ),
                                  )
                                else if (_stockOutWarehouseStockRows.isEmpty)
                                  Text(
                                    'No warehouse stock found for this selection.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.mutedTextColor(context),
                                    ),
                                  )
                                else
                                  ..._stockOutWarehouseStockRows.map((row) {
                                    final wid =
                                        row['warehouse_id']?.toString() ?? '';
                                    final name =
                                        row['warehouse_name']?.toString() ??
                                            'Warehouse';
                                    final location =
                                        row['location']?.toString() ?? '';
                                    final qty = row['available_quantity'];
                                    final isSelected = wid.isNotEmpty &&
                                        wid == _selectedWarehouseId;
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? AppTheme.primary.withValues(alpha: 0.08)
                                            : AppTheme.inputFillColor(context),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              location.isNotEmpty
                                                  ? '$name - $location'
                                                  : name,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color:
                                                    AppTheme.primaryTextColor(
                                                        context),
                                                fontWeight: isSelected
                                                    ? FontWeight.w700
                                                    : FontWeight.w500,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            'Qty: ${qty ?? 0}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.success,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                              ],
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
                        IgnorePointer(
                          ignoring: _isEditingOlderThan12Hours,
                          child: Opacity(
                            opacity: _isEditingOlderThan12Hours ? 0.6 : 1.0,
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceColor(context),
                                borderRadius:
                                    BorderRadius.circular(AppTheme.radiusLG),
                                border: Border.all(
                                    color: AppTheme.borderColor(context)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: selectedColorValue,
                                  isExpanded: true,
                                  icon: Icon(Icons.keyboard_arrow_down_rounded,
                                      color: AppTheme.mutedTextColor(context)),
                                  items: _selectedProduct != null &&
                                          (!_usesSourceStock
                                              ? _selectedProduct!
                                                  .colorStocks.isNotEmpty
                                              : stockOutColorRowsDeduped
                                                  .isNotEmpty)
                                      ? (_usesSourceStock
                                          ? stockOutColorRowsDeduped.map((c) {
                                              final cName =
                                                  c['color_name']?.toString() ??
                                                      'Default';
                                              final cQty =
                                                  c['available_quantity'] ?? 0;
                                              return DropdownMenuItem(
                                                value: cName,
                                                child: Text(
                                                  '$cName ($cQty)',
                                                  style: TextStyle(
                                                      fontSize: 13,
                                                      color: AppTheme
                                                          .primaryTextColor(
                                                              context)),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              );
                                            }).toList()
                                          : _selectedProduct!.colorStocks
                                              .map((c) {
                                              return DropdownMenuItem(
                                                value: c.color,
                                                child: Text(
                                                  '${c.color} (${c.quantity})',
                                                  style: TextStyle(
                                                      fontSize: 13,
                                                      color: AppTheme
                                                          .primaryTextColor(
                                                              context)),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              );
                                            }).toList())
                                      : [
                                          DropdownMenuItem(
                                            value: 'Default',
                                            child: Text(
                                              'Default',
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  color:
                                                      AppTheme.primaryTextColor(
                                                          context)),
                                            ),
                                          ),
                                        ],
                                  onChanged: _isEditingOlderThan12Hours
                                      ? null
                                      : (val) {
                                          if (val != null) {
                                            setState(() {
                                              _selectedColor = val;
                                            });
                                            _refreshStockOutWarehouses(
                                                autoRouteWarehouse: true,
                                                autoRouteColor: false);
                                          }
                                        },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              if (_isShift) ...[
                Text(
                  'TO WAREHOUSE *',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: AppTheme.mutedTextColor(context),
                  ),
                ),
                const SizedBox(height: 8),
                IgnorePointer(
                  ignoring: _isEditingOlderThan12Hours,
                  child: Opacity(
                    opacity: _isEditingOlderThan12Hours ? 0.6 : 1.0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceColor(context),
                        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                        border:
                            Border.all(color: AppTheme.borderColor(context)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedDestinationValue,
                          isExpanded: true,
                          hint: Text(
                            'Select destination warehouse',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.mutedTextColor(context),
                            ),
                          ),
                          icon: Icon(Icons.keyboard_arrow_down_rounded,
                              color: AppTheme.mutedTextColor(context)),
                          items: destinationWarehouseOptions.isEmpty
                              ? [
                                  DropdownMenuItem(
                                    value: '__none__',
                                    child: Text(
                                      'No destination warehouse',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: AppTheme.primaryTextColor(
                                              context)),
                                    ),
                                  ),
                                ]
                              : destinationWarehouseOptions.map((w) {
                                  final name =
                                      w['name']?.toString() ?? 'Warehouse';
                                  final loc = w['location']?.toString() ?? '';
                                  final display =
                                      loc.isNotEmpty ? '$name - $loc' : name;
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
                          onChanged: _isEditingOlderThan12Hours
                              ? null
                              : (val) {
                                  if (val == null || val.startsWith('__')) {
                                    return;
                                  }
                                  setState(() => _toWarehouseId = val);
                                },
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // CARTONS, PCS & TOTAL QUANTITY
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
                          enabled: !_isEditingOlderThan12Hours,
                          keyboardType: TextInputType.number,
                          style: TextStyle(
                              fontSize: 14,
                              color: _isEditingOlderThan12Hours
                                  ? AppTheme.mutedTextColor(context)
                                  : AppTheme.primaryTextColor(context)),
                          decoration: InputDecoration(
                            hintText: 'e.g. 5',
                            hintStyle: TextStyle(
                                color: AppTheme.mutedTextColor(context),
                                fontSize: 13),
                            fillColor: _isEditingOlderThan12Hours
                                ? AppTheme.inputFillColor(context)
                                    .withValues(alpha: 0.5)
                                : AppTheme.inputFillColor(context),
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 14),
                            enabledBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusLG),
                              borderSide: BorderSide(
                                  color: AppTheme.borderColor(context)),
                            ),
                            disabledBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusLG),
                              borderSide: BorderSide(
                                  color: AppTheme.borderColor(context)
                                      .withValues(alpha: 0.5)),
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
                          'pcs / carton',
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
                          enabled: !_isEditingOlderThan12Hours,
                          keyboardType: TextInputType.number,
                          style: TextStyle(
                              fontSize: 14,
                              color: _isEditingOlderThan12Hours
                                  ? AppTheme.mutedTextColor(context)
                                  : AppTheme.primaryTextColor(context)),
                          decoration: InputDecoration(
                            hintText: 'e.g. 20',
                            hintStyle: TextStyle(
                                color: AppTheme.mutedTextColor(context),
                                fontSize: 13),
                            fillColor: _isEditingOlderThan12Hours
                                ? AppTheme.inputFillColor(context)
                                    .withValues(alpha: 0.5)
                                : AppTheme.inputFillColor(context),
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 14),
                            enabledBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusLG),
                              borderSide: BorderSide(
                                  color: AppTheme.borderColor(context)),
                            ),
                            disabledBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusLG),
                              borderSide: BorderSide(
                                  color: AppTheme.borderColor(context)
                                      .withValues(alpha: 0.5)),
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
                          enabled: !_isEditingOlderThan12Hours,
                          keyboardType: TextInputType.number,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: _isEditingOlderThan12Hours
                                  ? AppTheme.mutedTextColor(context)
                                  : AppTheme.primaryTextColor(context)),
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
                            fillColor: _isEditingOlderThan12Hours
                                ? AppTheme.inputFillColor(context)
                                    .withValues(alpha: 0.5)
                                : AppTheme.inputFillColor(context),
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 14),
                            enabledBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusLG),
                              borderSide: BorderSide(
                                  color: AppTheme.borderColor(context)),
                            ),
                            disabledBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusLG),
                              borderSide: BorderSide(
                                  color: AppTheme.borderColor(context)
                                      .withValues(alpha: 0.5)),
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

              // RECORDED BY *
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
                enabled: !_isEditingOlderThan12Hours,
                style: TextStyle(
                    fontSize: 14,
                    color: _isEditingOlderThan12Hours
                        ? AppTheme.mutedTextColor(context)
                        : AppTheme.primaryTextColor(context)),
                validator: (val) => val == null || val.trim().isEmpty
                    ? 'Recorded By is required'
                    : null,
                decoration: InputDecoration(
                  hintText: 'Ashish',
                  fillColor: _isEditingOlderThan12Hours
                      ? AppTheme.inputFillColor(context).withValues(alpha: 0.5)
                      : AppTheme.inputFillColor(context),
                  filled: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                    borderSide:
                        BorderSide(color: AppTheme.borderColor(context)),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                    borderSide: BorderSide(
                        color: AppTheme.borderColor(context).withValues(alpha: 0.5)),
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

              // NOTES
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

              // ACTION BUTTONS
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _type == TransactionType.stockIn
                      ? AppTheme.success
                      : _isShift
                          ? AppTheme.primary
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
                            _isEditing
                                ? Icons.save_rounded
                                : (_isShift
                                    ? Icons.swap_horiz_rounded
                                    : _type == TransactionType.stockIn
                                        ? Icons.arrow_upward_rounded
                                        : Icons.arrow_downward_rounded),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isEditing
                                ? 'Save Changes'
                                : (_isShift
                                    ? 'Shift Stock'
                                    : _type == TransactionType.stockIn
                                        ? 'Record Stock In'
                                        : 'Record Stock Out'),
                            style: const TextStyle(
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
  final bool initialShowProductsDirectly;
  final String? helperText;

  const ProductPickerModal({
    super.key,
    required this.products,
    required this.onSelected,
    this.initialShowProductsDirectly = false,
    this.helperText,
  });

  @override
  State<ProductPickerModal> createState() => _ProductPickerModalState();
}

class _ProductPickerModalState extends State<ProductPickerModal> {
  String? _selectedCategory;
  String _searchQuery = '';
  late bool _showProductsDirectly;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _showProductsDirectly = widget.initialShowProductsDirectly;
  }

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
    final isRoot =
        _selectedCategory == null && !isSearching && !_showProductsDirectly;
    final shouldShowFolders =
        _selectedCategory == null && !isSearching && !_showProductsDirectly;

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
                        } else if (_showProductsDirectly) {
                          _showProductsDirectly = false;
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
                      : (_selectedCategory ??
                          (_showProductsDirectly
                              ? 'Choose product'
                              : 'Choose product code...')),
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
          const SizedBox(height: 10),

          if (widget.helperText != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.18)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 16,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.helperText!,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          if (!isSearching && _selectedCategory == null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppTheme.inputFillColor(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.borderColor(context)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _PickerModeButton(
                        label: 'Folders',
                        selected: !_showProductsDirectly,
                        onTap: () {
                          setState(() {
                            _showProductsDirectly = false;
                            _selectedCategory = null;
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: _PickerModeButton(
                        label: 'Products',
                        selected: _showProductsDirectly,
                        onTap: () {
                          setState(() {
                            _showProductsDirectly = true;
                            _selectedCategory = null;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

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
                hintText: 'Search product code...',
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
              child: shouldShowFolders
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
                                Icon(
                                  Icons.folder_rounded,
                                  size: 32,
                                  color: AppTheme.primary,
                                ),
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
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${p.name} - ${p.category}',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              color: AppTheme.mutedTextColor(
                                                  context),
                                              fontWeight: FontWeight.w600,
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

class _PickerModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PickerModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:
                selected ? Colors.white : AppTheme.secondaryTextColor(context),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
