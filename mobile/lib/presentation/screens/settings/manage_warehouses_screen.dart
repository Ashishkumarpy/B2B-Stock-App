import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/warehouses_provider.dart';
import '../../providers/api_client_provider.dart';
import '../../widgets/skeleton_loading.dart';

class ManageWarehousesScreen extends ConsumerWidget {
  const ManageWarehousesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warehousesAsync = ref.watch(warehousesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Warehouses'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_location_alt_rounded),
            onPressed: () => _showAddWarehouseDialog(context, ref),
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
                    Text('No warehouses yet',
                        style: TextStyle(
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Tap + to add your first warehouse',
                        style: TextStyle(
                            color: Colors.grey.shade400, fontSize: 12)),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(warehousesProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.all(AppTheme.sp16),
                  itemCount: warehouses.length,
                  itemBuilder: (context, index) {
                    final warehouse = warehouses[index];
                    final name = warehouse['name'] as String? ?? '?';
                    final location = warehouse['location'] as String? ?? '';
                    final code = warehouse['code'] as String? ?? '';
                    return Card(
                      margin: const EdgeInsets.only(bottom: AppTheme.sp12),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusLG)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.sp16, vertical: AppTheme.sp8),
                        leading: Container(
                          padding: const EdgeInsets.all(AppTheme.sp8),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withValues(alpha: 0.1),
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusMD),
                          ),
                          child: const Icon(Icons.warehouse_rounded,
                              color: AppTheme.success, size: 22),
                        ),
                        title: Text(name,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (location.isNotEmpty) Text(location),
                            if (code.isNotEmpty)
                              Text('Code: $code',
                                  style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 11)),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: AppTheme.danger),
                          onPressed: () =>
                              _confirmDelete(context, ref, warehouse),
                        ),
                      ),
                    );
                  },
                ),
              ),
        loading: () =>
            const Center(child: SkeletonList(count: 4, height: 80)),
        error: (err, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppTheme.danger, size: 48),
              const SizedBox(height: 16),
              Text('$err',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.danger)),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: () => ref.invalidate(warehousesProvider),
                  child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddWarehouseDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final locationController = TextEditingController();
    final codeController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Warehouse'),
        content: Column(
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
              controller: locationController,
              decoration: const InputDecoration(
                labelText: 'Location / Address',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: codeController,
              decoration: const InputDecoration(
                labelText: 'Code (optional)',
                prefixIcon: Icon(Icons.tag_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              try {
                final client = ref.read(apiClientProvider);
                await client.post('/warehouses', {
                  'name': name,
                  'location': locationController.text.trim(),
                  'code': codeController.text.trim(),
                });
                ref.invalidate(warehousesProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: AppTheme.danger),
                  );
                }
              }
            },
            child: const Text('Add Warehouse'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, WidgetRef ref, Map<String, dynamic> warehouse) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Warehouse'),
        content: Text(
            'Delete ${warehouse['name']}? Products linked to this warehouse will need to be reassigned.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              try {
                final client = ref.read(apiClientProvider);
                await client.delete('/warehouses/${warehouse['id']}');
                ref.invalidate(warehousesProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: AppTheme.danger),
                  );
                }
              }
            },
            child: const Text('Delete',
                style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
  }
}
