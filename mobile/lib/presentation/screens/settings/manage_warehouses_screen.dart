import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/api_client_provider.dart';
import '../../providers/warehouses_provider.dart';
import '../../widgets/connection_warning.dart';
import '../../widgets/skeleton_loading.dart';

class ManageWarehousesScreen extends ConsumerWidget {
  const ManageWarehousesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warehousesAsync = ref.watch(allWarehousesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Warehouses'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_location_alt_rounded),
            tooltip: 'Add warehouse',
            onPressed: () => _showWarehouseDialog(context, ref),
          ),
        ],
      ),
      body: warehousesAsync.when(
        data: (warehouses) => warehouses.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.warehouse_outlined,
                        size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text(
                      'No warehouses yet',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap + to add your first warehouse',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(allWarehousesProvider);
                  ref.invalidate(activeWarehousesProvider);
                },
                child: ListView.builder(
                  padding: const EdgeInsets.all(AppTheme.sp16),
                  itemCount: warehouses.length,
                  itemBuilder: (context, index) {
                    final warehouse = warehouses[index];
                    final name = warehouse['name'] as String? ?? 'Warehouse';
                    final location = warehouse['location'] as String? ?? '';
                    final code = warehouse['code'] as String? ?? '';
                    final locationUrl =
                        warehouse['location_url'] as String? ?? '';
                    final isActive = warehouse['is_active'] as bool? ?? true;

                    return Card(
                      margin: const EdgeInsets.only(bottom: AppTheme.sp12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.sp16,
                          vertical: 10,
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(AppTheme.sp8),
                          decoration: BoxDecoration(
                            color:
                                (isActive ? AppTheme.success : AppTheme.danger)
                                    .withValues(alpha: 0.1),
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusMD),
                          ),
                          child: Icon(
                            Icons.warehouse_rounded,
                            color:
                                isActive ? AppTheme.success : AppTheme.danger,
                            size: 22,
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? AppTheme.success.withValues(alpha: 0.12)
                                    : AppTheme.danger.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                isActive ? 'Active' : 'Inactive',
                                style: TextStyle(
                                  color: isActive
                                      ? AppTheme.success
                                      : AppTheme.danger,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (code.isNotEmpty)
                                Text(
                                  'Code: $code',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 11,
                                  ),
                                ),
                              if (location.isNotEmpty) Text(location),
                              if (locationUrl.isNotEmpty)
                                Text(
                                  locationUrl,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppTheme.primary,
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        trailing: TextButton.icon(
                          icon: const Icon(Icons.edit_rounded, size: 16),
                          label: const Text('Edit'),
                          onPressed: () => _showWarehouseDialog(
                            context,
                            ref,
                            warehouse: warehouse,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
        loading: () => const Center(child: SkeletonList(count: 4, height: 86)),
        error: (err, _) => ConnectionWarning(
          error: err,
          onRetry: () => ref.invalidate(allWarehousesProvider),
        ),
      ),
    );
  }

  void _showWarehouseDialog(
    BuildContext context,
    WidgetRef ref, {
    Map<String, dynamic>? warehouse,
  }) {
    final isEditing = warehouse != null;
    final nameController =
        TextEditingController(text: warehouse?['name']?.toString() ?? '');
    final codeController =
        TextEditingController(text: warehouse?['code']?.toString() ?? '');
    final locationController =
        TextEditingController(text: warehouse?['location']?.toString() ?? '');
    final locationUrlController = TextEditingController(
        text: warehouse?['location_url']?.toString() ?? '');
    var isActive = warehouse?['is_active'] as bool? ?? true;
    var isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text(isEditing ? 'Edit Warehouse' : 'Add Warehouse'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Warehouse Name *',
                      prefixIcon: Icon(Icons.warehouse_rounded),
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeController,
                    decoration: const InputDecoration(
                      labelText: 'Code',
                      prefixIcon: Icon(Icons.tag_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: locationController,
                    decoration: const InputDecoration(
                      labelText: 'Location / Address',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: locationUrlController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Location URL',
                      prefixIcon: Icon(Icons.map_outlined),
                    ),
                  ),
                  if (isEditing) ...[
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active warehouse'),
                      value: isActive,
                      onChanged: (value) {
                        setDialogState(() {
                          isActive = value;
                        });
                      },
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        final name = nameController.text.trim();
                        if (name.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('Warehouse name is required.'),
                              backgroundColor: AppTheme.danger,
                            ),
                          );
                          return;
                        }

                        setDialogState(() => isSaving = true);
                        try {
                          final client = ref.read(apiClientProvider);
                          final payload = {
                            'name': name,
                            'code': codeController.text.trim(),
                            'location': locationController.text.trim(),
                            'location_url': locationUrlController.text.trim(),
                            if (isEditing) 'is_active': isActive,
                          };

                          if (isEditing) {
                            await client.putJson(
                              '/warehouses/${warehouse['id']}',
                              payload,
                            );
                          } else {
                            await client.post('/warehouses', payload);
                          }

                          ref.invalidate(allWarehousesProvider);
                          ref.invalidate(activeWarehousesProvider);
                          if (ctx.mounted) Navigator.pop(ctx);
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: AppTheme.danger,
                              ),
                            );
                          }
                        } finally {
                          if (ctx.mounted) {
                            setDialogState(() => isSaving = false);
                          }
                        }
                      },
                child: Text(
                  isSaving
                      ? 'Saving...'
                      : isEditing
                          ? 'Save Changes'
                          : 'Add Warehouse',
                ),
              ),
            ],
          );
        },
      ),
    ).whenComplete(() {
      nameController.dispose();
      codeController.dispose();
      locationController.dispose();
      locationUrlController.dispose();
    });
  }
}
