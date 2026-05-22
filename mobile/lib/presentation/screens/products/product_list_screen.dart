import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../providers/products_provider.dart';
import '../../providers/categories_provider.dart';
import '../../providers/api_client_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/product_card.dart';
import '../../widgets/skeleton_loading.dart';
import '../../../domain/entities/product.dart';

class ProductListScreen extends ConsumerStatefulWidget {
  final String? initialFilter;
  final String? warehouseId;
  final String? warehouseName;

  const ProductListScreen({
    super.key,
    this.initialFilter,
    this.warehouseId,
    this.warehouseName,
  });

  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String? _openFolder; // null = folder view, string = inside a folder
  String _searchQuery = '';
  Set<String> _warehouseProductIds = <String>{};
  bool _isLoadingWarehouseProducts = false;
  String? _warehouseProductsError;

  @override
  void initState() {
    super.initState();
    if (widget.initialFilter != null &&
        widget.initialFilter != 'low' &&
        widget.initialFilter != 'in_stock') {
      _openFolder = widget.initialFilter;
    }
    _loadWarehouseProductsIfNeeded();
  }

  @override
  void didUpdateWidget(covariant ProductListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialFilter != oldWidget.initialFilter &&
        widget.initialFilter != null &&
        widget.initialFilter != 'low' &&
        widget.initialFilter != 'in_stock') {
      setState(() {
        _openFolder = widget.initialFilter;
      });
    }
    if (widget.warehouseId != oldWidget.warehouseId) {
      _loadWarehouseProductsIfNeeded();
    }
  }

  Future<void> _loadWarehouseProductsIfNeeded() async {
    final wid = widget.warehouseId?.trim();
    if (wid == null || wid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _warehouseProductIds = <String>{};
        _isLoadingWarehouseProducts = false;
        _warehouseProductsError = null;
      });
      return;
    }

    setState(() {
      _isLoadingWarehouseProducts = true;
      _warehouseProductsError = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final json = await client.get('/warehouses/$wid/products');
      final list = (json is Map ? json['data'] : null) as List? ?? const [];
      final ids = list
          .map((row) => (row as Map?)?['product_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      if (!mounted) return;
      setState(() {
        _warehouseProductIds = ids;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _warehouseProductsError = '$e';
        _warehouseProductIds = <String>{};
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoadingWarehouseProducts = false;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final role = ref.watch(currentUserProvider)?.role ?? UserRole.customer;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor(context),
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceColor(context),
        title: _openFolder != null
            ? Row(children: [
                Icon(Icons.folder_rounded, color: AppTheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.initialFilter == 'low'
                        ? '$_openFolder (Low Stock)'
                        : (widget.initialFilter == 'in_stock'
                            ? '$_openFolder (In Stock)'
                            : _openFolder!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ])
            : Text(
                widget.initialFilter == 'low'
                    ? 'Low Stock Products'
                    : (widget.initialFilter == 'in_stock'
                        ? 'In Stock Products'
                        : 'Products'),
              ),
        leading: _openFolder != null
            ? IconButton(
                icon: Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() => _openFolder = null),
              )
            : null,
        actions: [
          if (role.canManageProducts)
            IconButton(
              icon: Icon(Icons.add_box_rounded, color: AppTheme.primary),
              onPressed: () => context.go('/add-product'),
            ),
        ],
      ),
      body: Column(
        children: [
          if (widget.initialFilter == 'low')
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppTheme.danger.withValues(alpha: 0.08),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 14, color: AppTheme.danger),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Filtering: Low Stock Alerts Only',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.danger,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.go('/products'),
                    child: Text(
                      'Clear',
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
          if (widget.initialFilter == 'in_stock')
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppTheme.success.withValues(alpha: 0.08),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      size: 14, color: AppTheme.success),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Filtering: In-Stock Products Only',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.success,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.go('/products'),
                    child: Text(
                      'Clear',
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
          if (widget.warehouseId != null && widget.warehouseId!.trim().isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppTheme.primary.withValues(alpha: 0.08),
              child: Row(
                children: [
                  Icon(Icons.warehouse_rounded,
                      size: 14, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Warehouse: ${widget.warehouseName?.trim().isNotEmpty == true ? widget.warehouseName : 'Selected'}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.go('/products'),
                    child: const Text(
                      'Clear',
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
          // Search bar
          Container(
            color: AppTheme.surfaceColor(context),
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
              decoration: InputDecoration(
                hintText: _openFolder != null
                    ? 'Search in $_openFolder...'
                    : 'Search folders or products...',
                prefixIcon: Icon(Icons.search_rounded,
                    size: 20, color: AppTheme.mutedTextColor(context)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        })
                    : null,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ),

          // Main content
          Expanded(
            child: productsAsync.when(
              data: (allProducts) {
                if (_isLoadingWarehouseProducts) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: SkeletonList(count: 4, height: 160),
                  );
                }
                if (_warehouseProductsError != null) {
                  return Center(
                    child: Text(
                      _warehouseProductsError!,
                      style: TextStyle(color: AppTheme.danger),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                final sourceProducts = (widget.warehouseId != null &&
                        widget.warehouseId!.trim().isNotEmpty)
                    ? allProducts
                        .where((p) => _warehouseProductIds.contains(p.id))
                        .toList()
                    : allProducts;
                final isWarehouseMode =
                    widget.warehouseId != null && widget.warehouseId!.trim().isNotEmpty;

                // ── Search mode (cross-folder) ──
                if (_searchQuery.isNotEmpty) {
                  final results = sourceProducts
                      .where((p) =>
                          p.name
                              .toLowerCase()
                              .contains(_searchQuery.toLowerCase()) ||
                          p.code
                              .toLowerCase()
                              .contains(_searchQuery.toLowerCase()))
                      .toList();
                  return _buildProductGrid(results, 'Search Results', role);
                }

                // ── Warehouse mode should always show products directly ──
                if (isWarehouseMode) {
                  var warehouseProducts = sourceProducts;
                  if (widget.initialFilter == 'in_stock') {
                    warehouseProducts =
                        warehouseProducts.where((p) => p.quantity > 0).toList();
                  } else if (widget.initialFilter == 'low') {
                    warehouseProducts = warehouseProducts
                        .where((p) => p.quantity <= p.threshold)
                        .toList();
                  }
                  return _buildProductGrid(
                      warehouseProducts,
                      widget.warehouseName?.trim().isNotEmpty == true
                          ? '${widget.warehouseName} Products'
                          : 'Warehouse Products',
                      role);
                }

                // ── Inside a folder ──
                if (_openFolder != null) {
                  var folderProducts = sourceProducts
                      .where((p) => p.category == _openFolder)
                      .toList();

                  if (widget.initialFilter == 'in_stock') {
                    folderProducts =
                        folderProducts.where((p) => p.quantity > 0).toList();
                  } else if (widget.initialFilter == 'low') {
                    folderProducts = folderProducts
                        .where((p) => p.quantity <= p.threshold)
                        .toList();
                  }

                  return _buildProductGrid(folderProducts, _openFolder!, role);
                }

                // ── Folder view (default) ──
                return categoriesAsync.when(
                  data: (categories) {
                    if (categories.isEmpty) {
                      return _buildEmptyFolders(role);
                    }

                    // Build folder summaries
                    final folders = categories.map((cat) {
                      final catProds = sourceProducts
                          .where((p) => p.category == cat)
                          .toList();
                      final sampleImg = catProds
                          .where((p) =>
                              p.imageUrl != null && p.imageUrl!.isNotEmpty)
                          .map((p) => p.imageUrl!)
                          .firstOrNull;
                      final totalQty =
                          catProds.fold<int>(0, (s, p) => s + p.quantity);
                      final alerts = catProds
                          .where((p) => p.quantity <= p.threshold)
                          .length;
                      return _FolderData(
                        name: cat,
                        count: catProds.length,
                        totalQty: totalQty,
                        alerts: alerts,
                        sampleImage: sampleImg,
                      );
                    }).toList();

                    var foldersList = folders;
                    if (widget.initialFilter == 'in_stock') {
                      foldersList =
                          folders.where((f) => f.totalQty > 0).toList();
                    } else if (widget.initialFilter == 'low') {
                      foldersList = folders.where((f) => f.alerts > 0).toList();
                    }

                    return RefreshIndicator(
                      color: AppTheme.primary,
                      onRefresh: () async => ref.invalidate(productsProvider),
                      child: GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 1.0,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: foldersList.length,
                        itemBuilder: (context, index) {
                          return _FolderCard(
                            folder: foldersList[index],
                            onTap: () => setState(
                                () => _openFolder = foldersList[index].name),
                          );
                        },
                      ),
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.all(12),
                    child: SkeletonList(count: 4, height: 160),
                  ),
                  error: (e, _) => Center(child: Text('$e')),
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.all(12),
                child: SkeletonList(count: 4, height: 160),
              ),
              error: (err, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        color: AppTheme.danger, size: 48),
                    const SizedBox(height: 12),
                    Text('$err',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.danger)),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => ref.invalidate(productsProvider),
                      child: Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductGrid(
      List<Product> products, String title, UserRole role) {
    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No products found',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.secondaryTextColor(context))),
          ],
        ),
      );
    }

    // Sort products by their code/SKU alphabetically
    final sortedProducts = List<Product>.from(products);
    sortedProducts
        .sort((a, b) => a.code.toLowerCase().compareTo(b.code.toLowerCase()));

    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: () async => ref.invalidate(productsProvider),
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.62,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: sortedProducts.length,
        itemBuilder: (context, index) {
          final product = sortedProducts[index];
          return ProductCard(
            product: product,
            onTap: () => context.push('/products/${product.id}'),
            onEdit: role.canManageProducts
                ? () => context.push('/edit-product', extra: product)
                : null,
            onDelete: role.canManageProducts
                ? () => _confirmDeleteProduct(context, ref, product)
                : null,
          );
        },
      ),
    );
  }

  Widget _buildEmptyFolders(UserRole role) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open_rounded,
              size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No folders yet',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.secondaryTextColor(context),
                  fontSize: 16)),
          const SizedBox(height: 8),
          Text('Add products with categories to see folders here',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppTheme.mutedTextColor(context), fontSize: 12)),
          if (role.canManageProducts) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.go('/add-product'),
              icon: Icon(Icons.add_rounded),
              label: Text('Add Product'),
            ),
          ],
        ],
      ),
    );
  }

  void _confirmDeleteProduct(
      BuildContext context, WidgetRef ref, Product product) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusXL),
          ),
          title: Row(
            children: [
              Icon(Icons.delete_forever_rounded, color: AppTheme.danger),
              const SizedBox(width: 8),
              const Expanded(child: Text('Delete Product?')),
            ],
          ),
          content: Text(
            'Are you sure you want to permanently delete "${product.name}" (${product.code})?\n\n'
            'This action cannot be undone and will delete all stock history for this item.',
            style: TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel',
                  style: TextStyle(color: AppTheme.mutedTextColor(context))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.danger,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                ),
              ),
              onPressed: () async {
                Navigator.pop(context);

                // Show loading
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) => const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  ),
                );

                try {
                  final client = ref.read(apiClientProvider);
                  await client.delete('/products/${product.id}');

                  ref.invalidate(productsProvider);
                  ref.invalidate(categoriesProvider);

                  if (context.mounted) {
                    Navigator.pop(context); // Pop loading
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            'Product "${product.name}" deleted successfully.'),
                        backgroundColor: AppTheme.success,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    Navigator.pop(context); // Pop loading
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to delete product: $e'),
                        backgroundColor: AppTheme.danger,
                      ),
                    );
                  }
                }
              },
              child: Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}

// ─── Folder Data Model ──────────────────────────────────────
class _FolderData {
  final String name;
  final int count;
  final int totalQty;
  final int alerts;
  final String? sampleImage;

  const _FolderData({
    required this.name,
    required this.count,
    required this.totalQty,
    required this.alerts,
    this.sampleImage,
  });
}

// ─── Folder Card ────────────────────────────────────────────
class _FolderCard extends StatelessWidget {
  final _FolderData folder;
  final VoidCallback onTap;

  const _FolderCard({
    required this.folder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background image or colour
            folder.sampleImage != null
                ? CachedNetworkImage(
                    imageUrl: folder.sampleImage!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        Container(color: AppTheme.primaryLight),
                    errorWidget: (_, __, ___) =>
                        Container(color: AppTheme.primaryLight),
                  )
                : Container(
                    color: AppTheme.primaryLight,
                    child: const Center(
                      child: Icon(Icons.folder_rounded,
                          color: AppTheme.primary, size: 48),
                    ),
                  ),

            // Gradient overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.75),
                  ],
                ),
              ),
            ),

            // Info overlay at bottom
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            folder.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '${folder.count}',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _MiniStat(label: 'Qty', value: '${folder.totalQty}'),
                        if (folder.alerts > 0)
                          _MiniStat(
                            label: 'Alerts',
                            value: '${folder.alerts}',
                            isAlert: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final bool isAlert;

  const _MiniStat(
      {required this.label, required this.value, this.isAlert = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isAlert
            ? AppTheme.warning.withValues(alpha: 0.3)
            : Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 9,
          color: isAlert ? AppTheme.warning : Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
