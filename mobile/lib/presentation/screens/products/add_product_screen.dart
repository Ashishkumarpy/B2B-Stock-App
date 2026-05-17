import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/product.dart';
import '../../providers/api_client_provider.dart';
import '../../providers/categories_provider.dart';

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
  String? _selectedCategory;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.productToEdit?.name);
    _codeController = TextEditingController(text: widget.productToEdit?.code);
    _priceController =
        TextEditingController(text: widget.productToEdit?.price.toString());
    _thresholdController =
        TextEditingController(text: widget.productToEdit?.threshold.toString());
    _selectedCategory = widget.productToEdit?.category;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _priceController.dispose();
    _thresholdController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final client = ref.read(apiClientProvider);
      final data = {
        'name': _nameController.text,
        'code': _codeController.text,
        'price': double.parse(_priceController.text),
        'threshold': int.parse(_thresholdController.text),
        'category': _selectedCategory ?? 'Uncategorized',
      };

      if (widget.productToEdit != null) {
        await client.patch('/products/${widget.productToEdit!.id}', data);
      } else {
        await client.post('/products', data);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Product ${widget.productToEdit != null ? 'updated' : 'added'} successfully')),
        );
        context.pop();
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

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
            widget.productToEdit != null ? 'Edit Product' : 'Add New Product'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.sp24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                    labelText: 'Product Name',
                    prefixIcon: Icon(Icons.label_outline)),
                validator: (val) =>
                    val == null || val.isEmpty ? 'Enter name' : null,
              ),
              const SizedBox(height: AppTheme.sp16),
              TextFormField(
                controller: _codeController,
                decoration: const InputDecoration(
                    labelText: 'Product Code / SKU',
                    prefixIcon: Icon(Icons.qr_code_rounded)),
                validator: (val) =>
                    val == null || val.isEmpty ? 'Enter code' : null,
              ),
              const SizedBox(height: AppTheme.sp16),
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(
                    labelText: 'Category',
                    prefixIcon: Icon(Icons.folder_open_rounded)),
                items: (categories.value ?? [])
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (val) => setState(() => _selectedCategory = val),
              ),
              const SizedBox(height: AppTheme.sp16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _priceController,
                      decoration: const InputDecoration(
                          labelText: 'Price',
                          prefixIcon: Icon(Icons.attach_money_rounded)),
                      keyboardType: TextInputType.number,
                      validator: (val) =>
                          val == null || val.isEmpty ? 'Enter price' : null,
                    ),
                  ),
                  const SizedBox(width: AppTheme.sp16),
                  Expanded(
                    child: TextFormField(
                      controller: _thresholdController,
                      decoration: const InputDecoration(
                          labelText: 'Alert Threshold',
                          prefixIcon:
                              Icon(Icons.notifications_active_outlined)),
                      keyboardType: TextInputType.number,
                      validator: (val) =>
                          val == null || val.isEmpty ? 'Enter threshold' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.sp32),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Save Product'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
