import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/workers_provider.dart';
import '../../providers/api_client_provider.dart';
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
            onPressed: () => _showAddWorkerDialog(context, ref),
          ),
        ],
      ),
      body: workersAsync.when(
        data: (workers) => workers.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.people_outline_rounded,
                        size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text('No workers yet',
                        style: TextStyle(
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Tap + to add your first worker',
                        style: TextStyle(
                            color: Colors.grey.shade400, fontSize: 12)),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(workersProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.all(AppTheme.sp16),
                  itemCount: workers.length,
                  itemBuilder: (context, index) {
                    final worker = workers[index];
                    final name = worker['name'] as String? ?? '?';
                    final phone = worker['phone'] as String? ?? '';
                    final isActive = worker['is_active'] as bool? ?? true;
                    return Card(
                      margin: const EdgeInsets.only(bottom: AppTheme.sp12),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusLG)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.sp16, vertical: AppTheme.sp8),
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                          child: Text(
                            name[0].toUpperCase(),
                            style: const TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(name,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (phone.isNotEmpty) Text(phone),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? AppTheme.success.withValues(alpha: 0.1)
                                    : Colors.grey.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isActive ? 'Active' : 'Inactive',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isActive
                                      ? AppTheme.success
                                      : Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: AppTheme.danger),
                          onPressed: () =>
                              _confirmDelete(context, ref, worker),
                        ),
                      ),
                    );
                  },
                ),
              ),
        loading: () =>
            const Center(child: SkeletonList(count: 5, height: 80)),
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
                  onPressed: () => ref.invalidate(workersProvider),
                  child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddWorkerDialog(BuildContext context, WidgetRef ref) {
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
              decoration: const InputDecoration(
                labelText: 'Full Name *',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone Number (+91...)',
                prefixIcon: Icon(Icons.phone_android_rounded),
              ),
              keyboardType: TextInputType.phone,
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
              final phone = phoneController.text.trim();
              if (name.isEmpty || phone.isEmpty) return;
              try {
                final client = ref.read(apiClientProvider);
                await client.post('/workers', {
                  'name': name,
                  'phone': phone,
                  'role': 'worker',
                });
                ref.invalidate(workersProvider);
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
            child: const Text('Add Worker'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, WidgetRef ref, Map<String, dynamic> worker) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Worker'),
        content: Text(
            'Remove ${worker['name']}? Their transaction history will be preserved.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              try {
                final client = ref.read(apiClientProvider);
                await client.delete('/workers/${worker['id']}');
                ref.invalidate(workersProvider);
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
            child: const Text('Remove',
                style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
  }
}
