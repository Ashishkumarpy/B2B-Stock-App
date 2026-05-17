import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../providers/products_provider.dart';
import '../../providers/api_client_provider.dart';
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
  final _notesController = TextEditingController();

  Product? _selectedProduct;
  TransactionType _type = TransactionType.stockOut;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialType != null) _type = widget.initialType!;

    // Auto-select product if ID is provided
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.productId != null) {
        final products = ref.read(productsProvider).value ?? [];
        final match =
            products.where((p) => p.id == widget.productId).firstOrNull;
        if (match != null) {
          setState(() => _selectedProduct = match);
        }
      }
    });
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _handleScanner() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: MobileScanner(
          onDetect: (capture) {
            final barcode = capture.barcodes.first;
            if (barcode.rawValue != null) {
              Navigator.pop(context, barcode.rawValue);
            }
          },
        ),
      ),
    );

    if (result != null && mounted) {
      final products = ref.read(productsProvider).value ?? [];
      final match = products.where((p) => p.code == result).firstOrNull;
      if (match != null) {
        setState(() => _selectedProduct = match);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No product found with code: $result')),
        );
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _selectedProduct == null) return;

    setState(() => _isSubmitting = true);
    try {
      final client = ref.read(apiClientProvider);
      await client.post('/transactions', {
        'product_id': _selectedProduct!.id,
        'type': _type == TransactionType.stockIn ? 'IN' : 'OUT',
        'quantity': int.parse(_qtyController.text),
        'notes': _notesController.text,
        'warehouse_id': 'default', // Assuming a default warehouse for now
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaction recorded successfully')),
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
    final products = ref.watch(productsProvider).value ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Stock Entry'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: _handleScanner,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.sp24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTypeSelector(),
              const SizedBox(height: AppTheme.sp24),

              // Product Dropdown
              DropdownButtonFormField<Product>(
                value: _selectedProduct,
                decoration: const InputDecoration(
                  labelText: 'Product',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
                items: products
                    .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text('${p.code} - ${p.name}'),
                        ))
                    .toList(),
                onChanged: (val) => setState(() => _selectedProduct = val),
                validator: (val) =>
                    val == null ? 'Please select a product' : null,
              ),
              const SizedBox(height: AppTheme.sp16),

              // Quantity
              TextFormField(
                controller: _qtyController,
                decoration: InputDecoration(
                  labelText: 'Quantity',
                  prefixIcon: const Icon(Icons.calculate_outlined),
                  suffixText: _selectedProduct?.unit ?? 'pcs',
                ),
                keyboardType: TextInputType.number,
                validator: (val) {
                  if (val == null || val.isEmpty) return 'Enter quantity';
                  if (int.tryParse(val) == null) return 'Enter a valid number';
                  return null;
                },
              ),
              const SizedBox(height: AppTheme.sp16),

              // Notes
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (Optional)',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: AppTheme.sp32),

              ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Save Entry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TypeButton(
              label: 'STOCK OUT',
              isActive: _type == TransactionType.stockOut,
              color: AppTheme.danger,
              onTap: () => setState(() => _type = TransactionType.stockOut),
            ),
          ),
          Expanded(
            child: _TypeButton(
              label: 'STOCK IN',
              isActive: _type == TransactionType.stockIn,
              color: AppTheme.success,
              onTap: () => setState(() => _type = TransactionType.stockIn),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color color;
  final VoidCallback onTap;

  const _TypeButton({
    required this.label,
    required this.isActive,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMD - 2),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusMD - 2),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isActive ? Colors.white : AppTheme.textSecondary,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
