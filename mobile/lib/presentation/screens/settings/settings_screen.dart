import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/version_check_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_mode_provider.dart';
import '../../providers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final settings = ref.watch(settingsProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isDarkMode = themeMode == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.sp16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(AppTheme.sp16),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(AppTheme.radiusLG),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    child: Text(
                      user?.name.isNotEmpty == true
                          ? user!.name[0].toUpperCase()
                          : 'U',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTheme.sp16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Flexible(
                              child: Text(
                                user?.name ?? 'User',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (user != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                '${user.role.name[0].toUpperCase()}${user.role.name.substring(1)}',
                                style: TextStyle(
                                  color: Colors.grey.shade300,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          user?.email ?? '',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.sp24),
            const _SectionHeader(title: 'Appearance'),
            _SettingsCard(children: [
              _SwitchTile(
                icon: isDarkMode
                    ? Icons.dark_mode_rounded
                    : Icons.light_mode_rounded,
                label: 'Dark Mode',
                subtitle: 'Enable dark theme throughout the app',
                value: isDarkMode,
                onChanged: (v) =>
                    ref.read(themeModeProvider.notifier).setDarkMode(v),
              ),
            ]),
            const SizedBox(height: AppTheme.sp24),
            const _SectionHeader(title: 'Notifications'),
            _SettingsCard(children: [
              _SwitchTile(
                icon: Icons.notifications_rounded,
                label: 'Push Notifications',
                subtitle: 'Enable all app notifications',
                value: settings.pushNotifications,
                onChanged: (v) =>
                    ref.read(settingsProvider.notifier).setPushNotifications(v),
              ),
              const Divider(height: 1),
              _SwitchTile(
                icon: Icons.warning_rounded,
                iconColor: AppTheme.warning,
                label: 'Low Stock Alerts',
                subtitle: 'Notify when items fall below threshold',
                value: settings.lowStockAlerts,
                enabled: settings.pushNotifications,
                onChanged: (v) =>
                    ref.read(settingsProvider.notifier).setLowStockAlerts(v),
              ),
              const Divider(height: 1),
              _SwitchTile(
                icon: Icons.summarize_rounded,
                iconColor: AppTheme.primary,
                label: 'Weekly Report',
                subtitle: 'Receive a weekly stock summary',
                value: settings.weeklyReport,
                onChanged: (v) =>
                    ref.read(settingsProvider.notifier).setWeeklyReport(v),
              ),
              const Divider(height: 1),
              _SwitchTile(
                icon: Icons.system_update_rounded,
                iconColor: AppTheme.primary,
                label: 'In-App Update Alerts',
                subtitle: 'Notify when new updates are available',
                value: settings.inAppUpdates,
                onChanged: (v) =>
                    ref.read(settingsProvider.notifier).setInAppUpdates(v),
              ),
            ]),
            const SizedBox(height: AppTheme.sp24),
            const _SectionHeader(title: 'App Info'),
            _SettingsCard(children: [
              _InfoTile(
                icon: Icons.inventory_rounded,
                label: 'App Name',
                value: AppConstants.appName,
              ),
              const Divider(height: 1),
              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) {
                  return _InfoTile(
                    icon: Icons.tag_rounded,
                    label: 'Version',
                    value: snapshot.data?.version ?? '1.0.0',
                  );
                },
              ),
              const Divider(height: 1),
              _ActionTile(
                icon: Icons.system_update_rounded,
                iconColor: AppTheme.primary,
                label: 'Check for Updates',
                subtitle: 'Manually check for latest version',
                onTap: () =>
                    VersionCheckService.check(context, ref, force: true),
              ),
              const Divider(height: 1),
              _ActionTile(
                icon: Icons.bug_report_rounded,
                iconColor: Colors.teal,
                label: 'System Logs',
                subtitle: 'View diagnostic logs',
                onTap: () => context.push('/debug-logs'),
              ),
            ]),
            const SizedBox(height: AppTheme.sp24),
            const _SectionHeader(title: 'Legal'),
            _SettingsCard(children: [
              _ActionTile(
                icon: Icons.privacy_tip_outlined,
                iconColor: AppTheme.primary,
                label: 'Privacy Policy',
                subtitle: 'How we collect and use your data',
                onTap: () => _showPrivacyPolicy(context),
              ),
            ]),
            const SizedBox(height: AppTheme.sp24),
            const _SectionHeader(title: 'Account'),
            _SettingsCard(children: [
              _ActionTile(
                icon: Icons.verified_user_outlined,
                label: 'Refresh Access',
                iconColor: AppTheme.primary,
                subtitle: 'Sync your latest permissions from the server',
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final token = await ref
                      .read(authStateProvider.notifier)
                      .refreshAccessToken();
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(token != null
                          ? 'Access refreshed'
                          : 'Could not refresh access. Check your connection.'),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              if (user?.canManageWarehouses == true) ...[
                _ActionTile(
                  icon: Icons.warehouse_rounded,
                  label: 'Manage Warehouses',
                  iconColor: AppTheme.primary,
                  onTap: () => context.push('/manage-warehouses'),
                ),
                const Divider(height: 1),
              ],
              if (user?.canManageUsers == true) ...[
                _ActionTile(
                  icon: Icons.people_rounded,
                  label: 'Manage Workers',
                  iconColor: AppTheme.primary,
                  onTap: () => context.push('/manage-workers'),
                ),
                const Divider(height: 1),
              ],
              _ActionTile(
                icon: Icons.logout_rounded,
                label: 'Sign Out',
                iconColor: AppTheme.danger,
                labelColor: AppTheme.danger,
                onTap: () async {
                  final shouldSignOut = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Sign Out'),
                      content: const Text('Are you sure you want to sign out?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                          child: const Text('Sign Out',
                              style: TextStyle(color: AppTheme.danger)),
                        ),
                      ],
                    ),
                  );
                  if (shouldSignOut != true) return;
                  await ref.read(authStateProvider.notifier).logout();
                },
              ),
            ]),
            const SizedBox(height: AppTheme.sp32),
            Center(
              child: Text(
                '${AppConstants.appName} · ${AppConstants.appTagline}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPrivacyPolicy(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Privacy Policy'),
        content: const SingleChildScrollView(
          child: Text(
            'We collect only data required to run inventory operations, secure accounts, and provide reporting features. Data is stored securely in Supabase and access is role-based.',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close')),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(children: children),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    this.iconColor = AppTheme.primary,
    required this.label,
    required this.subtitle,
    required this.value,
    this.enabled = true,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: iconColor, size: 22),
      title: Text(label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: Switch(
        value: value,
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey, size: 22),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      trailing: Text(value,
          style:
              const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? subtitle;
  final Color? labelColor;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.subtitle,
    this.labelColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: iconColor, size: 22),
      title: Text(
        label,
        style: TextStyle(
            color: labelColor, fontWeight: FontWeight.bold, fontSize: 14),
      ),
      subtitle: subtitle != null
          ? Text(subtitle!, style: const TextStyle(fontSize: 12))
          : null,
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
    );
  }
}
