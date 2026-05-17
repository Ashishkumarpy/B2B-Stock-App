import 'package:equatable/equatable.dart';
import '../../core/constants/app_constants.dart';

/// A stock movement record (IN or OUT)
class Transaction extends Equatable {
  final String id;
  final String productId;
  final String workerId;
  final String productName;
  final String workerName;
  final String? colorName;
  final String? warehouseId;
  final String? warehouseName;
  final TransactionType type;
  final int quantity;
  final String? notes;
  final DateTime createdAt;

  Transaction({
    required this.id,
    required this.productId,
    String? workerId,
    String? userId,
    this.productName = '',
    this.workerName = '',
    this.colorName,
    this.warehouseId,
    this.warehouseName,
    required this.type,
    required this.quantity,
    this.notes,
    DateTime? createdAt,
    DateTime? timestamp,
  })  : workerId = workerId ?? userId ?? '',
        createdAt =
            createdAt ?? timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);

  bool get isStockIn => type == TransactionType.stockIn;
  bool get isStockOut => type == TransactionType.stockOut;
  String get userId => workerId;
  DateTime get timestamp => createdAt;

  @override
  List<Object?> get props => [
        id,
        productId,
        workerId,
        productName,
        workerName,
        colorName,
        warehouseId,
        warehouseName,
        type,
        quantity,
        notes,
        createdAt
      ];
}
