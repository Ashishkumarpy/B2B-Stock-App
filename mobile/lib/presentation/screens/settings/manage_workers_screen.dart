import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/workers_provider.dart';
import '../../widgets/skeleton_loading.dart';

class ManageWorkersScreen extends ConsumerWidget {
  const ManageWorkersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workersAsync = ref.watch(workersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Workers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _showAddWorkerDialog(context),
          ),
        ],
      ),
      body: workersAsync.when(
        data: (workers) => ListView.builder(
          padding: const EdgeInsets.all(AppTheme.sp16),
          itemCount: workers.length,
          itemBuilder: (context, index) {
            final worker = workers[index];
            return Card(
              margin: const EdgeInsets.only(bottom: AppTheme.sp12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLG)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppTheme.primary.withOpacity(0.1),
                  child: Text(
                    worker['name'][0].toUpperCase(),
                    style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(worker['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(worker['phone'] ?? 'No phone'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger),
                  onPressed: () => _confirmDelete(context, worker),
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

  void _showAddWorkerDialog(BuildContext context) {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Worker'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Full Name'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'Phone Number'),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                await Supabase.instance.client.from('workers').insert({
                  'name': nameController.text,
                  'phone': phoneController.text,
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

  void _confirmDelete(BuildContext context, Map<String, dynamic> worker) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Worker'),
        content: Text('Are you sure you want to delete ${worker['name']}? This will not delete their transaction history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              await Supabase.instance.client.from('workers').delete().eq('id', worker['id']);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Delete', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
  }
}
