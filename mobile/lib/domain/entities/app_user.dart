import 'package:equatable/equatable.dart';
import '../../core/constants/app_constants.dart';

class UserPermissions extends Equatable {
  final bool products;
  final bool inventory;
  final bool orders;
  final bool reports;
  final bool users;
  final bool settings;

  const UserPermissions({
    this.products = false,
    this.inventory = false,
    this.orders = false,
    this.reports = false,
    this.users = false,
    this.settings = false,
  });

  factory UserPermissions.defaultsForRole(UserRole role) {
    return switch (role) {
      UserRole.admin => const UserPermissions(
          products: true,
          inventory: true,
          orders: true,
          reports: true,
          users: true,
          settings: true,
        ),
      UserRole.manager => const UserPermissions(
          inventory: true,
          orders: true,
          reports: true,
          users: true,
        ),
      UserRole.worker => const UserPermissions(inventory: true),
      UserRole.customer => const UserPermissions(),
    };
  }

  factory UserPermissions.fromJson(Map<String, dynamic>? json, UserRole role) {
    if (json == null) return UserPermissions.defaultsForRole(role);
    return UserPermissions(
      products: _readBool(json, 'perm_products'),
      inventory: _readBool(json, 'perm_inventory'),
      orders: _readBool(json, 'perm_orders'),
      reports: _readBool(json, 'perm_reports'),
      users: _readBool(json, 'perm_users'),
      settings: _readBool(json, 'perm_settings'),
    );
  }

  Map<String, dynamic> toJson() => {
        'perm_products': products,
        'perm_inventory': inventory,
        'perm_orders': orders,
        'perm_reports': reports,
        'perm_users': users,
        'perm_settings': settings,
      };

  static bool _readBool(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value.toLowerCase() == 'true';
    return false;
  }

  @override
  List<Object?> get props =>
      [products, inventory, orders, reports, users, settings];
}

class AppUser extends Equatable {
  final String id;
  final String name;
  final String email;
  final UserRole role;
  final String? phone;
  final DateTime? createdAt;
  final UserPermissions? permissions;

  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.phone,
    this.createdAt,
    this.permissions,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'role': role.name,
        'phone': phone,
        'createdAt': createdAt?.toIso8601String(),
        'permissions': effectivePermissions.toJson(),
      };

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final role = UserRole.values.firstWhere(
      (e) => e.name == json['role'],
      orElse: () => UserRole.worker,
    );
    final rawPermissions = json['permissions'];
    return AppUser(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'User',
      email: json['email']?.toString() ?? '',
      role: role,
      phone: json['phone']?.toString(),
      createdAt:
          json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
      permissions: rawPermissions is Map
          ? UserPermissions.fromJson(
              Map<String, dynamic>.from(rawPermissions),
              role,
            )
          : UserPermissions.defaultsForRole(role),
    );
  }

  UserPermissions get effectivePermissions => role == UserRole.admin
      ? UserPermissions.defaultsForRole(role)
      : permissions ?? UserPermissions.defaultsForRole(role);

  bool get canManageProducts => effectivePermissions.products;
  bool get canRecordStock => effectivePermissions.inventory;
  bool get canViewStockActivity => effectivePermissions.inventory;
  bool get canViewAnalytics => effectivePermissions.reports;
  bool get canViewWorkerActivity => effectivePermissions.users;
  bool get canManageUsers => effectivePermissions.users;
  bool get canManageWarehouses => effectivePermissions.settings;
  bool get canManageSuppliers => effectivePermissions.settings;

  @override
  List<Object?> get props =>
      [id, name, email, role, phone, createdAt, permissions];
}
