import 'package:equatable/equatable.dart';
import '../../core/constants/app_constants.dart';

class AppUser extends Equatable {
  final String id;
  final String name;
  final String email;
  final UserRole role;
  final String? phone;
  final DateTime? createdAt;

  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.phone,
    this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'role': role.name,
    'phone': phone,
    'createdAt': createdAt?.toIso8601String(),
  };

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'],
    name: json['name'],
    email: json['email'],
    role: UserRole.values.firstWhere((e) => e.name == json['role'], orElse: () => UserRole.worker),
    phone: json['phone'],
    createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
  );

  @override
  List<Object?> get props => [id, name, email, role, phone, createdAt];
}
