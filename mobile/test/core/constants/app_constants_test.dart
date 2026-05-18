import 'package:b2b_stock_app/core/constants/app_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserRole permissions', () {
    test('admin has full operational access', () {
      expect(UserRole.admin.canManageUsers, isTrue);
      expect(UserRole.admin.canManageProducts, isTrue);
      expect(UserRole.admin.canManageWarehouses, isTrue);
      expect(UserRole.admin.canViewAnalytics, isTrue);
      expect(UserRole.admin.canViewWorkerActivity, isTrue);
      expect(UserRole.admin.canViewStockActivity, isTrue);
      expect(UserRole.admin.canRecordStock, isTrue);
    });

    test('manager can review operations but cannot manage users or products',
        () {
      expect(UserRole.manager.canManageUsers, isFalse);
      expect(UserRole.manager.canManageProducts, isFalse);
      expect(UserRole.manager.canManageWarehouses, isTrue);
      expect(UserRole.manager.canViewAnalytics, isTrue);
      expect(UserRole.manager.canViewWorkerActivity, isTrue);
      expect(UserRole.manager.canViewStockActivity, isTrue);
      expect(UserRole.manager.canRecordStock, isTrue);
    });

    test('worker gets stock entry, product lookup, and activity history access',
        () {
      expect(UserRole.worker.canManageUsers, isFalse);
      expect(UserRole.worker.canManageProducts, isFalse);
      expect(UserRole.worker.canManageWarehouses, isFalse);
      expect(UserRole.worker.canViewAnalytics, isFalse);
      expect(UserRole.worker.canViewWorkerActivity, isFalse);
      expect(UserRole.worker.canViewStockActivity, isTrue);
      expect(UserRole.worker.canRecordStock, isTrue);
    });
  });
}
