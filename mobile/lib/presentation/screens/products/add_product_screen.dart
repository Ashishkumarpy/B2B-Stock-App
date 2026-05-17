import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/product.dart';
import '../../providers/api_client_provider.dart';
import '../../providers/categories_provider.dart';
import '../../providers/products_provider.dart';

class AddProductScreen extends ConsumerStatefulWidget {
  final Product? productToEdit;

  const AddProductScreen({super.key, this.productToEdit});

  @override
  ConsumerState<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends ConsumerState<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _nameController;
  late TextEditingController _codeController;
  late TextEditingController _priceController;
  late TextEditingController _thresholdController;
  late TextEditingController _quantityController;
  late TextEditingController _descriptionController;
  late TextEditingController _unitController;
  late TextEditingController _costPriceController;
  
  // Images editing state
  late TextEditingController _mainImageUrlController;
  late TextEditingController _newExtraImageUrlController;
  List<String> _extraImages = [];

  // Color stocks editing state
  List<Map<String, dynamic>> _colorStocks = [];
  bool _syncQuantityFromColors = false;

  String? _selectedCategory;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    
    _nameController = TextEditingController(text: widget.productToEdit?.name);
    _codeController = TextEditingController(text: widget.productToEdit?.code);
    _priceController =
        TextEditingController(text: widget.productToEdit?.price.toString() ?? '');
    _thresholdController =
        TextEditingController(text: widget.productToEdit?.threshold.toString() ?? '50');
    _quantityController =
        TextEditingController(text: widget.productToEdit?.quantity.toString() ?? '0');
    _descriptionController =
        TextEditingController(text: widget.productToEdit?.description ?? '');
    _unitController =
        TextEditingController(text: widget.productToEdit?.unit ?? 'Units');
    _costPriceController =
        TextEditingController(text: widget.productToEdit?.costPrice?.toString() ?? '0');

    // Load initial images
    _mainImageUrlController =
        TextEditingController(text: widget.productToEdit?.imageUrl ?? '');
    _newExtraImageUrlController = TextEditingController();
    
    if (widget.productToEdit != null) {
      final allImgs = widget.productToEdit!.images;
      // Filter out main image from secondary list to avoid duplicates
      final mainUrl = widget.productToEdit!.imageUrl ?? '';
      _extraImages = allImgs
          .map((img) => img.url)
          .where((url) => url.isNotEmpty && url != mainUrl)
          .toList();
    }

    // Load initial colors
    if (widget.productToEdit != null) {
      _colorStocks = widget.productToEdit!.colorStocks
          .map((c) => {'color': c.color, 'quantity': c.quantity})
          .toList();
      _syncQuantityFromColors = _colorStocks.isNotEmpty;
    }

    _selectedCategory = widget.productToEdit?.category;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _priceController.dispose();
    _thresholdController.dispose();
    _quantityController.dispose();
    _descriptionController.dispose();
    _unitController.dispose();
    _costPriceController.dispose();
    _mainImageUrlController.dispose();
    _newExtraImageUrlController.dispose();
    super.dispose();
  }

  int get _colorTotalQuantity => _colorStocks.fold<int>(
      0, (sum, item) => sum + (item['quantity'] as int));

  void _addColorStock() {
    setState(() {
      _colorStocks.add({'color': '', 'quantity': 0});
      _syncQuantityFromColors = true; // Auto-enable sync when colors are added
    });
  }

  void _removeColorStock(int index) {
    setState(() {
      _colorStocks.removeAt(index);
      if (_colorStocks.isEmpty) {
        _syncQuantityFromColors = false;
      }
    });
  }

  void _addExtraImage() {
    final url = _newExtraImageUrlController.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _extraImages.add(url);
      _newExtraImageUrlController.clear();
    });
  }

  void _removeExtraImage(int index) {
    setState(() {
      _extraImages.removeAt(index);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final client = ref.read(apiClientProvider);
      
      final finalQuantity = _syncQuantityFromColors
          ? _colorTotalQuantity
          : (int.tryParse(_quantityController.text) ?? 0);

      final finalColorStocks = _colorStocks
          .where((item) => (item['color'] as String).trim().isNotEmpty)
          .map((item) => {
                'color': (item['color'] as String).trim(),
                'quantity': item['quantity'] as int,
              })
          .toList();

      final finalImages = [
        if (_mainImageUrlController.text.trim().isNotEmpty)
          {
            'url': _mainImageUrlController.text.trim(),
            'publicId': '',
          },
        ..._extraImages
            .where((url) => url.trim().isNotEmpty)
            .map((url) => {'url': url.trim(), 'publicId': ''}),
      ];

      final data = {
        'name': _nameController.text.trim(),
        'code': _codeController.text.trim(),
        'price': double.parse(_priceController.text),
        'threshold': int.parse(_thresholdController.text),
        'category': _selectedCategory ?? 'Uncategorized',
        'quantity': finalQuantity,
        'color_stocks': finalColorStocks,
        'images': finalImages,
        'image_url': finalImages.isNotEmpty ? finalImages.first['url'] : null,
        'description': _descriptionController.text.trim(),
        'unit': _unitController.text.trim().isEmpty ? 'Units' : _unitController.text.trim(),
        'cost_price': double.tryParse(_costPriceController.text) ?? 0.0,
      };

      if (widget.productToEdit != null) {
        await client.putJson('/products/${widget.productToEdit!.id}', data);
      } else {
        await client.post('/products', data);
      }

      // Invalidate products provider so the local lists update instantly
      ref.invalidate(productsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Product ${widget.productToEdit != null ? 'updated' : 'added'} successfully'),
            backgroundColor: AppTheme.success,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        foregroundColor: AppTheme.textPrimary,
        scrolledUnderElevation: 0,
        title: Text(
          widget.productToEdit != null ? 'Edit Product' : 'Add New Product',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.sp16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Basic Info Section ──
              _sectionHeader('Basic Information'),
              const SizedBox(height: 8),
              
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Product Name *',
                  prefixIcon: Icon(Icons.label_outline),
                ),
                validator: (val) =>
                    val == null || val.isEmpty ? 'Enter name' : null,
              ),
              const SizedBox(height: AppTheme.sp16),
              
              TextFormField(
                controller: _codeController,
                decoration: const InputDecoration(
                  labelText: 'Product Code / SKU *',
                  prefixIcon: Icon(Icons.qr_code_rounded),
                ),
                validator: (val) =>
                    val == null || val.isEmpty ? 'Enter code / SKU' : null,
              ),
              const SizedBox(height: AppTheme.sp16),
              
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Category *',
                  prefixIcon: Icon(Icons.folder_open_rounded),
                ),
                items: (categories.value ?? [])
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (val) => setState(() => _selectedCategory = val),
                validator: (val) => val == null ? 'Select category' : null,
              ),
              
              const SizedBox(height: 24),

              // ── Pricing & Specifications Section ──
              _sectionHeader('Pricing & Specifications'),
              const SizedBox(height: 8),
              
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _priceController,
                      decoration: const InputDecoration(
                        labelText: 'Price (₹) *',
                        prefixIcon: Icon(Icons.attach_money_rounded),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (val) =>
                          val == null || val.isEmpty ? 'Enter price' : null,
                    ),
                  ),
                  const SizedBox(width: AppTheme.sp12),
                  Expanded(
                    child: TextFormField(
                      controller: _costPriceController,
                      decoration: const InputDecoration(
                        labelText: 'Cost Price (₹)',
                        prefixIcon: Icon(Icons.money_off_rounded),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.sp16),
              
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _thresholdController,
                      decoration: const InputDecoration(
                        labelText: 'Alert Threshold *',
                        prefixIcon: Icon(Icons.notifications_active_outlined),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (val) =>
                          val == null || val.isEmpty ? 'Enter threshold' : null,
                    ),
                  ),
                  const SizedBox(width: AppTheme.sp12),
                  Expanded(
                    child: TextFormField(
                      controller: _unitController,
                      decoration: const InputDecoration(
                        labelText: 'Unit (e.g. Boxes, Pcs)',
                        prefixIcon: Icon(Icons.workspaces_outline),
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 24),

              // ── Inventory Count Section ──
              _sectionHeader('Inventory Stock'),
              const SizedBox(height: 8),
              
              TextFormField(
                controller: _quantityController,
                enabled: !_syncQuantityFromColors,
                decoration: InputDecoration(
                  labelText: _syncQuantityFromColors
                      ? 'Total Stock (Synced: $_colorTotalQuantity)'
                      : 'Stock Quantity *',
                  prefixIcon: const Icon(Icons.inventory_2_outlined),
                  fillColor: _syncQuantityFromColors ? Colors.grey.shade100 : null,
                ),
                keyboardType: TextInputType.number,
                validator: (val) {
                  if (_syncQuantityFromColors) return null;
                  return val == null || val.isEmpty ? 'Enter quantity' : null;
                },
              ),
              
              const SizedBox(height: 24),

              // ── Color Stock Sub-Section ──
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Color Stocks Breakdown',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _addColorStock,
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('Add Color', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    if (_colorStocks.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'No color-wise stock added. Add colors below to track item variables.',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                        ),
                      )
                    else ...[
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _colorStocks.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = _colorStocks[index];
                          return Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextFormField(
                                  initialValue: item['color'],
                                  decoration: const InputDecoration(
                                    labelText: 'Color Name',
                                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  ),
                                  onChanged: (val) {
                                    item['color'] = val;
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  initialValue: item['quantity'].toString(),
                                  decoration: const InputDecoration(
                                    labelText: 'Qty',
                                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  ),
                                  keyboardType: TextInputType.number,
                                  onChanged: (val) {
                                    setState(() {
                                      item['quantity'] = int.tryParse(val) ?? 0;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 20),
                                onPressed: () => _removeColorStock(index),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Checkbox(
                            value: _syncQuantityFromColors,
                            onChanged: (val) {
                              setState(() {
                                _syncQuantityFromColors = val ?? false;
                              });
                            },
                          ),
                          const Expanded(
                            child: Text(
                              'Auto-sync main stock quantity from color values',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Image Gallery Section ──
              _sectionHeader('Product Gallery Images'),
              const SizedBox(height: 8),
              
              TextFormField(
                controller: _mainImageUrlController,
                decoration: const InputDecoration(
                  labelText: 'Main Banner Image URL',
                  prefixIcon: Icon(Icons.image_outlined),
                  hintText: 'https://res.cloudinary.com/...',
                ),
              ),
              const SizedBox(height: 16),
              
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Supplementary Images',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _newExtraImageUrlController,
                            decoration: const InputDecoration(
                              labelText: 'Paste Supplementary Image URL',
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _addExtraImage,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(60, 42),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                            ),
                          ),
                          child: const Icon(Icons.add, size: 20),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    if (_extraImages.isEmpty)
                      const Text(
                        'No extra images added. Add URLs above to build a multi-image swipeable gallery.',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _extraImages.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, idx) {
                          final url = _extraImages[idx];
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.background,
                              borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: CachedNetworkImage(
                                    imageUrl: url,
                                    width: 32,
                                    height: 32,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => Container(color: Colors.grey.shade200),
                                    errorWidget: (_, __, ___) => const Icon(Icons.broken_image, size: 16),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    url,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, color: AppTheme.danger, size: 18),
                                  onPressed: () => _removeExtraImage(idx),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Description Section ──
              _sectionHeader('Description'),
              const SizedBox(height: 8),
              
              TextFormField(
                controller: _descriptionController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Product Details / Notes',
                  alignLabelWithHint: true,
                  hintText: 'Enter sizes, materials, instructions...',
                ),
              ),

              const SizedBox(height: AppTheme.sp32),
              
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        widget.productToEdit != null ? 'Update Product' : 'Create Product',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 14,
        color: AppTheme.primary,
        letterSpacing: 0.3,
      ),
    );
  }
}
