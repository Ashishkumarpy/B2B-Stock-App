import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/connection_messages.dart';
import '../../providers/api_client_provider.dart';
import '../../providers/products_provider.dart';

class BulkImportProductsScreen extends ConsumerStatefulWidget {
  const BulkImportProductsScreen({super.key});

  @override
  ConsumerState<BulkImportProductsScreen> createState() =>
      _BulkImportProductsScreenState();
}

class _BulkImportProductsScreenState
    extends ConsumerState<BulkImportProductsScreen> {
  bool _isImporting = false;
  List<List<dynamic>>? _csvData;
  String? _fileName;

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        final fields = csv.decode(content);

        setState(() {
          _csvData = fields;
          _fileName = result.files.single.name;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error picking file: $e'),
              backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Future<void> _importData() async {
    if (_csvData == null || _csvData!.length <= 1) return;

    setState(() => _isImporting = true);
    try {
      final client = ref.read(apiClientProvider);
      final headers =
          _csvData![0].map((e) => e.toString().trim().toLowerCase()).toList();

      final List<Map<String, dynamic>> productsToInsert = [];

      for (var i = 1; i < _csvData!.length; i++) {
        final row = _csvData![i];
        if (row.isEmpty) continue;

        final product = <String, dynamic>{};

        for (var j = 0; j < headers.length; j++) {
          if (j < row.length) {
            final key = headers[j];
            final value = row[j];

            if (key == 'quantity' || key == 'threshold' || key == 'price') {
              product[key] = num.tryParse(value.toString()) ?? 0;
            } else if (key == 'sku') {
              product['code'] = value.toString();
            } else {
              product[key] = value.toString();
            }
          }
        }

        // Ensure required fields (name and code/sku)
        if (product['name'] != null &&
            (product['code'] != null || product['sku'] != null)) {
          productsToInsert.add(product);
        }
      }

      if (productsToInsert.isNotEmpty) {
        for (final product in productsToInsert) {
          await client.post('/products', product);
        }
        ref.invalidate(productsProvider);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Successfully imported ${productsToInsert.length} products')),
          );
          Navigator.pop(context);
        }
      } else {
        throw 'No valid products found in CSV';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(userFriendlyErrorMessage(e)),
              backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bulk Import'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppTheme.sp24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildInstructions(),
            const SizedBox(height: 32),
            _buildFilePicker(),
            if (_csvData != null) ...[
              const SizedBox(height: 32),
              _buildDataPreview(),
            ],
            const Spacer(),
            ElevatedButton(
              onPressed:
                  (_csvData == null || _isImporting) ? null : _importData,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(AppTheme.sp16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusLG)),
              ),
              child: _isImporting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Confirm and Import Data',
                      style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructions() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.sp16),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  color: AppTheme.primary, size: 20),
              const SizedBox(width: 8),
              const Text('CSV Requirements',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: AppTheme.primary)),
            ],
          ),
          const SizedBox(height: 12),
          const Text('• First row must contain headers.',
              style: TextStyle(fontSize: 13)),
          const Text('• Required: name, code (or sku), category.',
              style: TextStyle(fontSize: 13)),
          const Text('• Optional: quantity, threshold, price.',
              style: TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildFilePicker() {
    return InkWell(
      onTap: _pickFile,
      borderRadius: BorderRadius.circular(AppTheme.radiusLG),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 40),
        decoration: BoxDecoration(
          border: Border.all(
              color: Colors.grey.withValues(alpha: 0.3),
              style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        ),
        child: Column(
          children: [
            const Icon(Icons.cloud_upload_outlined,
                size: 48, color: AppTheme.primary),
            const SizedBox(height: 12),
            Text(
              _fileName ?? 'Tap to select CSV file',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _fileName != null ? Colors.black87 : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Preview (${_csvData!.length - 1} records found)',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Container(
          height: 200,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
            borderRadius: BorderRadius.circular(AppTheme.radiusMD),
          ),
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: _csvData!.length > 5 ? 5 : _csvData!.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              return Text(
                _csvData![index].join(', '),
                style: TextStyle(
                  fontSize: 12,
                  color: index == 0 ? AppTheme.primary : Colors.black87,
                  fontWeight: index == 0 ? FontWeight.bold : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              );
            },
          ),
        ),
      ],
    );
  }
}
