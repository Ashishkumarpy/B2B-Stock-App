import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';

class MainShell extends ConsumerWidget {
  final Widget child;

  const MainShell({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentUserProvider)?.role ?? UserRole.customer;

    return Scaffold(
      body: child,
      bottomNavigationBar: _BottomNavBar(
        location: GoRouterState.of(context).uri.path,
        role: role,
      ),
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  final String location;
  final UserRole role;

  const _BottomNavBar({required this.location, required this.role});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor(context),
        border: Border(top: BorderSide(color: AppTheme.borderColor(context))),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: _NavBarItem(
                  icon: Icons.dashboard_outlined,
                  activeIcon: Icons.dashboard_rounded,
                  label: 'Dashboard',
                  isActive: location == '/',
                  onTap: () => context.go('/'),
                ),
              ),
              Expanded(
                child: _NavBarItem(
                  icon: Icons.inventory_2_outlined,
                  activeIcon: Icons.inventory_2_rounded,
                  label: 'Products',
                  isActive: location.startsWith('/products') ||
                      location == '/add-product',
                  onTap: () => context.go('/products'),
                ),
              ),
              if (role.canViewStockActivity)
                Expanded(
                  child: _NavBarItem(
                    icon: Icons.swap_vert_circle_outlined,
                    activeIcon: Icons.swap_vert_circle_rounded,
                    label: 'Activity',
                    isActive: location == '/stock-activity' ||
                        location == '/worker-activity',
                    onTap: () => context.go('/stock-activity'),
                  ),
                )
              else if (role.canRecordStock)
                Expanded(
                  child: _NavBarItem(
                    icon: Icons.swap_vert_circle_outlined,
                    activeIcon: Icons.swap_vert_circle_rounded,
                    label: 'Entry',
                    isActive: location == '/stock-entry',
                    onTap: () => context.go('/stock-entry'),
                  ),
                ),
              if (role.canViewAnalytics)
                Expanded(
                  child: _NavBarItem(
                    icon: Icons.analytics_outlined,
                    activeIcon: Icons.analytics_rounded,
                    label: 'Analytics',
                    isActive: location == '/analytics',
                    onTap: () => context.go('/analytics'),
                  ),
                ),
              Expanded(
                child: _NavBarItem(
                  icon: Icons.settings_outlined,
                  activeIcon: Icons.settings_rounded,
                  label: 'Settings',
                  isActive: location == '/settings',
                  onTap: () => context.go('/settings'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppTheme.primary : AppTheme.textMuted;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMD),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isActive ? activeIcon : icon, color: color, size: 22),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
