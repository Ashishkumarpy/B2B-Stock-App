import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/app_user.dart';
import '../../providers/workers_provider.dart';
import '../../providers/api_client_provider.dart';
import '../../widgets/connection_warning.dart';
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
        data: (workers) {
          final manageableWorkers =
              workers.where(_isManageableWorkerProfile).toList();
          return manageableWorkers.isEmpty
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
                    itemCount: manageableWorkers.length,
                    itemBuilder: (context, index) {
                      final worker = manageableWorkers[index];
                      final name = worker['name'] as String? ?? '?';
                      final phone = worker['phone'] as String? ?? '';
                      final isActive = worker['is_active'] as bool? ?? true;
                      final permissionLabels = _permissionLabels(worker);
                      return Card(
                        margin: const EdgeInsets.only(bottom: AppTheme.sp12),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusLG)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.sp16,
                              vertical: AppTheme.sp8),
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
                                  ...permissionLabels.map(
                                    (label) => Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.blue.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        label.toUpperCase(),
                                        style: const TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue,
                                        ),
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
                                        style:
                                            TextStyle(color: AppTheme.danger)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
        },
        loading: () => const Center(child: SkeletonList(count: 5, height: 80)),
        error: (err, _) => ConnectionWarning(
          error: err,
          onRetry: () => ref.invalidate(workersProvider),
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

  List<String> _permissionLabels(Map<String, dynamic> worker) {
    final labels = <String>[];
    if (_permissionValue(worker, 'perm_products')) labels.add('Products');
    if (_permissionValue(worker, 'perm_inventory')) labels.add('Inventory');
    if (_permissionValue(worker, 'perm_orders')) labels.add('Orders');
    if (_permissionValue(worker, 'perm_reports')) labels.add('Reports');
    if (_permissionValue(worker, 'perm_users')) labels.add('Workers');
    if (_permissionValue(worker, 'perm_settings')) labels.add('Settings');
    return labels.isEmpty ? ['No access'] : labels;
  }

  bool _isManageableWorkerProfile(Map<String, dynamic> worker) {
    final role = worker['role']?.toString().trim().toLowerCase();
    return role == 'worker' || role == 'manager';
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
  late bool _permProducts;
  late bool _permInventory;
  late bool _permOrders;
  late bool _permReports;
  late bool _permUsers;
  late bool _permSettings;
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
    final defaults = UserPermissions.defaultsForRole(_roleFromString(_role));
    _permProducts =
        _permissionValue(worker, 'perm_products', fallback: defaults.products);
    _permInventory = _permissionValue(worker, 'perm_inventory',
        fallback: worker?['can_access_stock'] as bool? ?? defaults.inventory);
    _permOrders =
        _permissionValue(worker, 'perm_orders', fallback: defaults.orders);
    _permReports =
        _permissionValue(worker, 'perm_reports', fallback: defaults.reports);
    _permUsers =
        _permissionValue(worker, 'perm_users', fallback: defaults.users);
    _permSettings =
        _permissionValue(worker, 'perm_settings', fallback: defaults.settings);
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
        'can_access_stock': _permInventory,
        'permissions': {
          'perm_products': _permProducts,
          'perm_inventory': _permInventory,
          'perm_orders': _permOrders,
          'perm_reports': _permReports,
          'perm_users': _permUsers,
          'perm_settings': _permSettings,
        },
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
                    description: 'Custom Access',
                    icon: Icons.manage_accounts_outlined,
                    selectedColor: Colors.purple,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.sp24),

            Text(
              'Section Access',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.secondaryTextColor(context),
              ),
            ),
            const SizedBox(height: AppTheme.sp8),
            _PermissionTile(
              title: 'Products',
              subtitle: 'Create, edit prices, and delete products',
              icon: Icons.inventory_2_outlined,
              value: _permProducts,
              onChanged: (val) => setState(() => _permProducts = val),
            ),
            _PermissionTile(
              title: 'Inventory',
              subtitle: 'Stock in, stock out, and activity logs',
              icon: Icons.swap_vert_circle_outlined,
              value: _permInventory,
              onChanged: (val) => setState(() => _permInventory = val),
            ),
            _PermissionTile(
              title: 'Orders',
              subtitle: 'Access order workflows when available',
              icon: Icons.receipt_long_outlined,
              value: _permOrders,
              onChanged: (val) => setState(() => _permOrders = val),
            ),
            _PermissionTile(
              title: 'Reports',
              subtitle: 'Analytics, reports, and exports',
              icon: Icons.analytics_outlined,
              value: _permReports,
              onChanged: (val) => setState(() => _permReports = val),
            ),
            _PermissionTile(
              title: 'Workers',
              subtitle: 'Manage workers and view worker activity',
              icon: Icons.people_outline_rounded,
              value: _permUsers,
              onChanged: (val) => setState(() => _permUsers = val),
            ),
            _PermissionTile(
              title: 'Settings',
              subtitle: 'Manage warehouses and app-level settings',
              icon: Icons.settings_outlined,
              value: _permSettings,
              onChanged: (val) => setState(() => _permSettings = val),
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
          _applyRoleDefaults(roleValue);
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

  void _applyRoleDefaults(String roleValue) {
    final defaults =
        UserPermissions.defaultsForRole(_roleFromString(roleValue));
    _permProducts = defaults.products;
    _permInventory = defaults.inventory;
    _permOrders = defaults.orders;
    _permReports = defaults.reports;
    _permUsers = defaults.users;
    _permSettings = defaults.settings;
  }
}

class _PermissionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PermissionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      secondary: Icon(icon, color: AppTheme.primary),
      value: value,
      activeThumbColor: AppTheme.primary,
      contentPadding: EdgeInsets.zero,
      onChanged: onChanged,
    );
  }
}

bool _permissionValue(
  Map<String, dynamic>? worker,
  String key, {
  bool fallback = false,
}) {
  final permissions = worker?['permissions'];
  final raw = worker?[key] ?? (permissions is Map ? permissions[key] : null);
  if (raw is bool) return raw;
  if (raw is num) return raw != 0;
  if (raw is String) return raw.toLowerCase() == 'true';
  return fallback;
}

UserRole _roleFromString(String role) {
  return UserRole.values.firstWhere(
    (value) => value.name == role,
    orElse: () => UserRole.worker,
  );
}
