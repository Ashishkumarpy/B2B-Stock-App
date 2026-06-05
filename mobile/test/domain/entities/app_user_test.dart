import 'package:b2b_stock_app/core/constants/app_constants.dart';
import 'package:b2b_stock_app/domain/entities/app_user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppUser permissions', () {
    test('admin always receives full effective access', () {
      const user = AppUser(
        id: 'admin-1',
        name: 'Admin',
        email: 'admin@example.com',
        role: UserRole.admin,
        permissions: UserPermissions(
          products: false,
          inventory: false,
          reports: false,
          users: false,
          settings: false,
        ),
      );

      expect(user.canManageProducts, isTrue);
      expect(user.canRecordStock, isTrue);
      expect(user.canViewAnalytics, isTrue);
      expect(user.canManageUsers, isTrue);
      expect(user.canManageWarehouses, isTrue);
    });

    test('parses server permissions from session json', () {
      final user = AppUser.fromJson({
        'id': 'manager-1',
        'name': 'Manager',
        'email': 'manager@example.com',
        'role': 'manager',
        'permissions': {
          'perm_products': false,
          'perm_inventory': true,
          'perm_reports': false,
          'perm_users': true,
          'perm_settings': false,
        },
      });

      expect(user.canManageProducts, isFalse);
      expect(user.canRecordStock, isTrue);
      expect(user.canViewAnalytics, isFalse);
      expect(user.canManageUsers, isTrue);
      expect(user.canManageWarehouses, isFalse);
    });

    test('uses role defaults when older sessions have no permissions', () {
      final user = AppUser.fromJson({
        'id': 'worker-1',
        'name': 'Worker',
        'email': '',
        'role': 'worker',
      });

      expect(user.canManageProducts, isFalse);
      expect(user.canRecordStock, isTrue);
      expect(user.canViewAnalytics, isFalse);
      expect(user.canManageUsers, isFalse);
    });
  });
}
