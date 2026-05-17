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
import 'product_detail_screen.dart';

class ColorStockInput {
  final TextEditingController colorController;
  final TextEditingController qtyController;

  ColorStockInput({
    required String color,
    required int quantity,
  })  : colorController = TextEditingController(text: color),
        qtyController = TextEditingController(text: quantity.toString());

  void dispose() {
    colorController.dispose();
    qtyController.dispose();
  }
}

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
  List<Map<String, String>> _productImages = [];
  String _mainImageUrl = '';
  bool _isUploadingImage = false;

  // Color stocks editing state
  List<ColorStockInput> _colorStockInputs = [];
  bool _syncQuantityFromColors = false;

  String? _selectedCategory;
  bool _isSubmitting = false;
  final List<String> _localCategories = [];

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
    if (widget.productToEdit != null) {
      _mainImageUrl = widget.productToEdit!.imageUrl ?? '';
      _productImages = widget.productToEdit!.images
          .map((img) => {
                'url': img.url,
                'publicId': img.publicId,
              })
          .toList();
      if (_mainImageUrl.isNotEmpty && !_productImages.any((img) => img['url'] == _mainImageUrl)) {
        _productImages.insert(0, {
          'url': _mainImageUrl,
          'publicId': '',
        });
      }
    }

    // Load initial colors
    if (widget.productToEdit != null) {
      _colorStockInputs = widget.productToEdit!.colorStocks
          .map((c) => ColorStockInput(color: c.color, quantity: c.quantity))
          .toList();
      _syncQuantityFromColors = _colorStockInputs.isNotEmpty;
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
    for (final input in _colorStockInputs) {
      input.dispose();
    }
    super.dispose();
  }

  int get _colorTotalQuantity => _colorStockInputs.fold<int>(
      0, (sum, item) => sum + (int.tryParse(item.qtyController.text) ?? 0));

  void _addColorStock() {
    setState(() {
      _colorStockInputs.add(ColorStockInput(color: '', quantity: 0));
      _syncQuantityFromColors = true; // Auto-enable sync when colors are added
    });
  }

  void _removeColorStock(int index) {
    setState(() {
      _colorStockInputs[index].dispose();
      _colorStockInputs.removeAt(index);
      if (_colorStockInputs.isEmpty) {
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
          final newImg = {
            'url': response['url']?.toString() ?? '',
            'publicId': response['publicId']?.toString() ?? response['public_id']?.toString() ?? '',
          };
          _productImages.add(newImg);
          if (_mainImageUrl.isEmpty) {
            _mainImageUrl = newImg['url']!;
          }
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

      final finalColorStocks = _colorStockInputs
          .where((item) => item.colorController.text.trim().isNotEmpty)
          .map((item) => {
                'color': item.colorController.text.trim(),
                'quantity': int.tryParse(item.qtyController.text.trim()) ?? 0,
              })
          .toList();

      final finalImages = _productImages
          .where((img) => img['url']!.trim().isNotEmpty)
          .map((img) => {
                'url': img['url']!.trim(),
                'publicId': img['publicId'] ?? '',
              })
          .toList();

      final data = {
        'name': _nameController.text.trim(),
        'code': _codeController.text.trim(),
        'price': double.parse(_priceController.text),
        'threshold': int.parse(_thresholdController.text),
        'category': _selectedCategory ?? 'Uncategorized',
        'quantity': finalQuantity,
        'color_stocks': finalColorStocks,
        'images': finalImages,
        'image_url': _mainImageUrl.isNotEmpty ? _mainImageUrl : (finalImages.isNotEmpty ? finalImages.first['url'] : null),
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

  void _showCreateCategoryDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Folder / Category', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter new category/folder name...',
            prefixIcon: Icon(Icons.folder_rounded),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = controller.text.trim();
              if (val.isNotEmpty) {
                setState(() {
                  _localCategories.add(val);
                  _selectedCategory = val;
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final fetchedCats = categoriesAsync.value ?? [];
    final Set<String> mergedCats = {...fetchedCats, ..._localCategories};
    if (_selectedCategory != null) {
      mergedCats.add(_selectedCategory!);
    }
    final sortedCats = mergedCats.toList()..sort();

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
                validator: (val) {
                  if (val == null || val.isEmpty) return 'Enter code';
                  final enteredCode = val.trim();
                  final products = ref.read(productsProvider).value ?? [];
                  final duplicate = products.any((p) =>
                      p.code.toLowerCase() == enteredCode.toLowerCase() &&
                      p.id != widget.productToEdit?.id);
                  if (duplicate) {
                    return 'This Product Code is already taken';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppTheme.sp16),
              
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedCategory,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Category *',
                        prefixIcon: Icon(Icons.folder_open_rounded),
                      ),
                      items: sortedCats
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (val) => setState(() => _selectedCategory = val),
                      validator: (val) => val == null ? 'Select category' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                      padding: const EdgeInsets.all(12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                      ),
                    ),
                    icon: const Icon(Icons.create_new_folder_rounded, color: AppTheme.primary),
                    onPressed: () => _showCreateCategoryDialog(context),
                  ),
                ],
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
                    if (_colorStockInputs.isEmpty)
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
                        itemCount: _colorStockInputs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = _colorStockInputs[index];
                          return Row(
                            key: ValueKey(item),
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextFormField(
                                  controller: item.colorController,
                                  decoration: const InputDecoration(
                                    labelText: 'Color Name',
                                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: item.qtyController,
                                  decoration: const InputDecoration(
                                    labelText: 'Qty',
                                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  ),
                                  keyboardType: TextInputType.number,
                                  onChanged: (val) {
                                    setState(() {});
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

          // ── Loading indicator ──
          if (_isUploadingImage) ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
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
            ),
            const SizedBox(height: 16),
          ],

          // ── Images Gallery Grid ──
          if (_productImages.isNotEmpty) ...[
            const Text(
              'Product Gallery & Management',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.82,
              ),
              itemCount: _productImages.length,
              itemBuilder: (context, index) {
                final img = _productImages[index];
                final url = img['url'] ?? '';
                final isMain = url == _mainImageUrl;

                return Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                    border: Border.all(
                      color: isMain ? AppTheme.primary : const Color(0xFFE2E8F0),
                      width: isMain ? 2 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            GestureDetector(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => FullScreenImageViewer(
                                      images: _productImages.map((img) => img['url']!).toList(),
                                      initialIndex: index,
                                    ),
                                  ),
                                );
                              },
                              child: CachedNetworkImage(
                                imageUrl: url,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(
                                  color: Colors.grey[100],
                                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                ),
                                errorWidget: (_, __, ___) => Container(
                                  color: Colors.grey[100],
                                  child: const Icon(Icons.broken_image, size: 32, color: AppTheme.textMuted),
                                ),
                              ),
                            ),
                            if (isMain)
                              Positioned(
                                top: 8,
                                left: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.star, color: Colors.white, size: 10),
                                      SizedBox(width: 4),
                                      Text(
                                        'Main',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Card Actions
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        color: Colors.grey[50],
                        child: Row(
                          children: [
                            // "Main" Toggle Button
                            Expanded(
                              child: InkWell(
                                onTap: isMain
                                    ? null
                                    : () {
                                        setState(() {
                                          _mainImageUrl = url;
                                        });
                                      },
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        isMain ? Icons.star : Icons.star_border,
                                        color: isMain ? Colors.amber.shade700 : AppTheme.textMuted,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        isMain ? 'Main' : 'Set Main',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: isMain ? FontWeight.bold : FontWeight.normal,
                                          color: isMain ? Colors.amber.shade900 : AppTheme.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const VerticalDivider(width: 1, color: Color(0xFFE2E8F0)),
                            // "Remove" Button
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 16),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                setState(() {
                                  _productImages.removeAt(index);
                                  if (isMain) {
                                    _mainImageUrl = _productImages.isNotEmpty
                                        ? _productImages.first['url'] ?? ''
                                        : '';
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ] else ...[
            Container(
              height: 100,
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
                      size: 26, color: Colors.indigo.shade300),
                  const SizedBox(height: 6),
                  const Text(
                    'No photos added yet',
                    style: TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Snap a photo or choose from gallery above',
                    style: TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
