import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/warehouses_provider.dart';
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
            onPressed: () => _showAddWarehouseDialog(context),
          ),
        ],
      ),
      body: warehousesAsync.when(
        data: (warehouses) => ListView.builder(
          padding: const EdgeInsets.all(AppTheme.sp16),
          itemCount: warehouses.length,
          itemBuilder: (context, index) {
            final warehouse = warehouses[index];
            return Card(
              margin: const EdgeInsets.only(bottom: AppTheme.sp12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLG)),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(AppTheme.sp8),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                  ),
                  child: Icon(Icons.warehouse_rounded, color: AppTheme.success, size: 20),
                ),
                title: Text(warehouse['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(warehouse['location'] ?? 'No location details'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger),
                  onPressed: () => _confirmDelete(context, warehouse),
                ),
              ),
            );
          },
        ),
        loading: () => const Center(child: SkeletonList(count: 5, height: 80)),
        error: (err, _) => Center(child: Text('Error: $err')),
      ),
    );
  }

  void _showAddWarehouseDialog(BuildContext context) {
    final nameController = TextEditingController();
    final locationController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Warehouse'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Warehouse Name'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: locationController,
              decoration: const InputDecoration(labelText: 'Location/Address'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                await Supabase.instance.client.from('warehouses').insert({
                  'name': nameController.text,
                  'location': locationController.text,
                });
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, Map<String, dynamic> warehouse) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Warehouse'),
        content: Text('Are you sure you want to delete ${warehouse['name']}? Products linked to this warehouse will need to be reassigned.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              await Supabase.instance.client.from('warehouses').delete().eq('id', warehouse['id']);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Delete', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
  }
}
