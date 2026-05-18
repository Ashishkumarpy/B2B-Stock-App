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
        title: Text('Manage Workers'),
        actions: [
          IconButton(
            icon: Icon(Icons.add_rounded),
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
                        size: 64, color: AppTheme.mutedTextColor(context)),
                    const SizedBox(height: 16),
                    Text('No workers yet',
                        style: TextStyle(
                            color: AppTheme.secondaryTextColor(context),
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Tap + to add your first worker',
                        style: TextStyle(
                            color: AppTheme.mutedTextColor(context),
                            fontSize: 12)),
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
                          backgroundColor:
                              AppTheme.primary.withValues(alpha: 0.1),
                          child: Text(
                            name[0].toUpperCase(),
                            style: TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(name,
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (phone.isNotEmpty) Text(phone),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                // Role Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: (worker['role'] == 'manager'
                                            ? Colors.purple
                                            : AppTheme.primary)
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    (worker['role'] as String? ?? 'worker')
                                        .toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: worker['role'] == 'manager'
                                          ? Colors.purple
                                          : AppTheme.primary,
                                    ),
                                  ),
                                ),
                                // Active / Inactive Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? AppTheme.success
                                            .withValues(alpha: 0.1)
                                        : Colors.grey.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isActive ? 'ACTIVE' : 'INACTIVE',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: isActive
                                          ? AppTheme.success
                                          : Colors.grey,
                                    ),
                                  ),
                                ),
                                // Stock Access Badge
                                if (worker['can_access_stock'] as bool? ?? true)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'STOCK ACCESS',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert_rounded),
                          onSelected: (value) {
                            if (value == 'edit') {
                              _showEditWorkerDialog(context, ref, worker);
                            } else if (value == 'delete') {
                              _confirmDelete(context, ref, worker);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit_outlined, size: 20),
                                  SizedBox(width: 8),
                                  Text('Edit'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline_rounded,
                                      size: 20, color: AppTheme.danger),
                                  SizedBox(width: 8),
                                  Text('Delete',
                                      style: TextStyle(color: AppTheme.danger)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
        loading: () => const Center(child: SkeletonList(count: 5, height: 80)),
        error: (err, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline_rounded,
                  color: AppTheme.danger, size: 48),
              const SizedBox(height: 16),
              Text('$err',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.danger)),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: () => ref.invalidate(workersProvider),
                  child: Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddWorkerDialog(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _WorkerFormBottomSheet(
        ref: ref,
      ),
    );
  }

  void _showEditWorkerDialog(
      BuildContext context, WidgetRef ref, Map<String, dynamic> worker) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _WorkerFormBottomSheet(
        ref: ref,
        workerToEdit: worker,
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, WidgetRef ref, Map<String, dynamic> worker) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove Worker'),
        content: Text(
            'Remove ${worker['name']}? Their transaction history will be preserved.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
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
            child: Text('Remove', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
  }
}

class _WorkerFormBottomSheet extends StatefulWidget {
  final WidgetRef ref;
  final Map<String, dynamic>? workerToEdit;

  const _WorkerFormBottomSheet({
    required this.ref,
    this.workerToEdit,
  });

  @override
  State<_WorkerFormBottomSheet> createState() => _WorkerFormBottomSheetState();
}

class _WorkerFormBottomSheetState extends State<_WorkerFormBottomSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late String _role;
  late bool _canAccessStock;
  late bool _isActive;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final worker = widget.workerToEdit;
    _nameController =
        TextEditingController(text: worker?['name'] as String? ?? '');
    _phoneController =
        TextEditingController(text: worker?['phone'] as String? ?? '');
    _emailController =
        TextEditingController(text: worker?['email'] as String? ?? '');
    _role = worker?['role'] as String? ?? 'worker';
    _canAccessStock = worker?['can_access_stock'] as bool? ?? true;
    _isActive = worker?['is_active'] as bool? ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a full name'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a phone number'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final client = widget.ref.read(apiClientProvider);
      final payload = {
        'name': name,
        'phone': phone,
        'role': _role,
        'can_access_stock': _canAccessStock,
        'is_active': _isActive,
        'email': email.isNotEmpty ? email : null,
      };

      if (widget.workerToEdit != null) {
        await client.putJson('/workers/${widget.workerToEdit!['id']}', payload);
      } else {
        await client.post('/workers', payload);
      }

      widget.ref.invalidate(workersProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.workerToEdit != null;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppTheme.radiusLG * 1.5),
          topRight: Radius.circular(AppTheme.radiusLG * 1.5),
        ),
      ),
      padding: EdgeInsets.only(
        left: AppTheme.sp24,
        right: AppTheme.sp24,
        top: AppTheme.sp16,
        bottom: AppTheme.sp24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Drag Handle
            Center(
              child: Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.borderColor(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppTheme.sp16),

            // Header
            Text(
              isEdit ? 'Edit Worker Profile' : 'Add New Worker',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.sp24),

            // Inputs
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Full Name *',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: AppTheme.sp16),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone Number (+91...) *',
                prefixIcon: Icon(Icons.phone_android_rounded),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: AppTheme.sp16),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email Address (Optional)',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: AppTheme.sp24),

            // Custom Role Selector
            Text(
              'Assign Role *',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.secondaryTextColor(context),
              ),
            ),
            const SizedBox(height: AppTheme.sp8),
            Row(
              children: [
                Expanded(
                  child: _buildRoleCard(
                    roleValue: 'worker',
                    title: 'Worker',
                    description: 'Staff / Entry',
                    icon: Icons.engineering_outlined,
                    selectedColor: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: AppTheme.sp12),
                Expanded(
                  child: _buildRoleCard(
                    roleValue: 'manager',
                    title: 'Manager',
                    description: 'Full Access',
                    icon: Icons.manage_accounts_outlined,
                    selectedColor: Colors.purple,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.sp24),

            // Toggles
            SwitchListTile(
              title: Text('Can Access Stock'),
              subtitle: Text('Allows recording stock movements'),
              value: _canAccessStock,
              activeThumbColor: AppTheme.primary,
              contentPadding: EdgeInsets.zero,
              onChanged: (val) {
                setState(() => _canAccessStock = val);
              },
            ),
            if (isEdit) ...[
              const Divider(),
              SwitchListTile(
                title: Text('Active Status'),
                subtitle: Text(_isActive
                    ? 'Worker can log in'
                    : 'Worker account is disabled'),
                value: _isActive,
                activeThumbColor: AppTheme.success,
                contentPadding: EdgeInsets.zero,
                onChanged: (val) {
                  setState(() => _isActive = val);
                },
              ),
            ],
            const SizedBox(height: AppTheme.sp24),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppTheme.sp12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _role == 'manager' ? Colors.purple : AppTheme.primary,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : Text(isEdit ? 'Save Changes' : 'Add Worker'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleCard({
    required String roleValue,
    required String title,
    required String description,
    required IconData icon,
    required Color selectedColor,
  }) {
    final isSelected = _role == roleValue;
    return GestureDetector(
      onTap: () {
        setState(() {
          _role = roleValue;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(AppTheme.sp12),
        decoration: BoxDecoration(
          color: isSelected
              ? selectedColor.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusLG),
          border: Border.all(
            color: isSelected ? selectedColor : AppTheme.borderColor(context),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 28,
              color:
                  isSelected ? selectedColor : AppTheme.mutedTextColor(context),
            ),
            const SizedBox(height: AppTheme.sp8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSelected
                    ? selectedColor
                    : AppTheme.primaryTextColor(context),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              description,
              style: TextStyle(
                fontSize: 10,
                color: isSelected
                    ? selectedColor.withValues(alpha: 0.8)
                    : AppTheme.mutedTextColor(context),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
