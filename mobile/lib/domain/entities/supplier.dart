import 'package:equatable/equatable.dart';

class Supplier extends Equatable {
  final String id;
  final String name;
  final String contactName;
  final String email;
  final String phone;
  final String? address;
  final List<String> productIds;
  final DateTime? createdAt;

  const Supplier({
    required this.id,
    required this.name,
    this.contactName = '',
    this.email = '',
    this.phone = '',
    this.address,
    this.productIds = const [],
    this.createdAt,
  });

  Supplier copyWith({
    String? id,
    String? name,
    String? contactName,
    String? email,
    String? phone,
    String? address,
    List<String>? productIds,
    DateTime? createdAt,
  }) {
    return Supplier(
      id: id ?? this.id,
      name: name ?? this.name,
      contactName: contactName ?? this.contactName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      productIds: productIds ?? this.productIds,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        contactName,
        email,
        phone,
        address,
        productIds,
        createdAt,
      ];
}
