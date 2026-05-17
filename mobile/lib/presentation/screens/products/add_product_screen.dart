import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
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
  bool _isUploadingImage = false;

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

  Future<void> _pickAndUploadImage(ImageSource source) async {
    final picker = ImagePicker();
    try {
      final XFile? pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      setState(() => _isUploadingImage = true);

      final client = ref.read(apiClientProvider);
      final response = await client.uploadFile('/uploads/image', pickedFile.path);

      if (response is Map && response.containsKey('url')) {
        setState(() {
          _mainImageUrlController.text = response['url'] ?? '';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Image uploaded successfully!'),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      } else {
        throw Exception('Invalid server response');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingImage = false);
      }
    }
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

      final existingExtraImages = widget.productToEdit != null
          ? widget.productToEdit!.images
              .where((img) => img.url != widget.productToEdit!.imageUrl)
              .map((img) => {
                    'url': img.url,
                    'publicId': img.publicId,
                  })
              .toList()
          : const [];

      final finalImages = [
        if (_mainImageUrlController.text.trim().isNotEmpty)
          {
            'url': _mainImageUrlController.text.trim(),
            'publicId': '',
          },
        ...existingExtraImages,
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
                  labelText: 'Product Code *',
                  prefixIcon: Icon(Icons.qr_code_rounded),
                ),
                validator: (val) =>
                    val == null || val.isEmpty ? 'Enter code' : null,
              ),
              const SizedBox(height: AppTheme.sp16),
              
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                isExpanded: true,
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
                        prefixText: '₹ ',
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
                        prefixText: '₹ ',
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
                        labelText: 'Threshold *',
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
                        labelText: 'Unit (e.g. Pcs)',
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
                              SizedBox(
                                width: 36,
                                height: 36,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 20),
                                  onPressed: () => _removeColorStock(index),
                                ),
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

              // ── Image Section ──
              _sectionHeader('Product Image'),
              const SizedBox(height: 8),
              _buildMainImageSection(),
              
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

  Widget _buildMainImageSection() {
    final currentUrl = _mainImageUrlController.text.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Nice triggers section on top of card ──
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _isUploadingImage ? null : () => _pickAndUploadImage(ImageSource.camera),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                      border: Border.all(color: AppTheme.primary.withOpacity(0.15)),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.camera_alt_outlined, color: AppTheme.primary, size: 24),
                        const SizedBox(height: 6),
                        const Text(
                          'Take Photo from Mobile',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Snap via camera instantly',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 9,
                            color: AppTheme.primary.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: _isUploadingImage ? null : () => _pickAndUploadImage(ImageSource.gallery),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.indigo.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                      border: Border.all(color: Colors.indigo.withOpacity(0.15)),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.photo_library_outlined, color: Colors.indigo.shade700, size: 24),
                        const SizedBox(height: 6),
                        const Text(
                          'Choose from your Mobile',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: Colors.indigo,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Select from your gallery',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.indigo.shade700.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),

          // ── Loading state or Preview state below ──
          if (_isUploadingImage)
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text(
                      'Uploading to secure server...',
                      style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            )
          else if (currentUrl.isNotEmpty)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                  child: CachedNetworkImage(
                    imageUrl: currentUrl,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      height: 200,
                      color: Colors.grey[100],
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      height: 200,
                      color: Colors.grey[100],
                      child: const Icon(Icons.broken_image,
                          size: 48, color: AppTheme.textMuted),
                    ),
                  ),
                ),
                // "Main Image" badge overlay at top-left
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star, color: Colors.amber.shade400, size: 14),
                        const SizedBox(width: 4),
                        const Text(
                          'Main Banner Photo',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // "Remove" button overlay at top-right
                Positioned(
                  top: 12,
                  right: 12,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _mainImageUrlController.clear();
                      });
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.shade900.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete_forever_outlined, color: Colors.white, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'Remove',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            )
          else
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                border: Border.all(
                  color: const Color(0xFFE2E8F0),
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_outlined,
                      size: 30, color: Colors.indigo.shade300),
                  const SizedBox(height: 8),
                  const Text(
                    'No photo captured yet',
                    style: TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Choose a method above to add product photo',
                    style: TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 10),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
