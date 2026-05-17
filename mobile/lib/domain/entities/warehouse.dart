import 'package:equatable/equatable.dart';

class Warehouse extends Equatable {
  final String id;
  final String name;
  final String? code;
  final String? location;
  final String? locationUrl;
  final bool isActive;
  final DateTime? createdAt;

  const Warehouse({
    required this.id,
    required this.name,
    this.code,
    this.location,
    this.locationUrl,
    this.isActive = true,
    this.createdAt,
  });

  Warehouse copyWith({
    String? id,
    String? name,
    String? code,
    String? location,
    String? locationUrl,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return Warehouse(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      location: location ?? this.location,
      locationUrl: locationUrl ?? this.locationUrl,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        code,
        location,
        locationUrl,
        isActive,
        createdAt,
      ];
}
