import '../../domain/entities/product.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/entities/supplier.dart';
import '../../domain/entities/app_user.dart';
import '../../core/constants/app_constants.dart';

/// Realistic mock data that mirrors the Firestore schema exactly.
/// Swap this with FirestoreDataSource to go live.
class MockDataSource {
  MockDataSource._();

  // ── Users ─────────────────────────────────────────────────────────────────
  static final List<AppUser> users = [
    AppUser(
      id: 'user_001',
      name: 'Rajesh Kumar',
      email: 'rajesh@stockiq.com',
      role: UserRole.admin,
      createdAt: DateTime(2024, 1, 10),
    ),
    AppUser(
      id: 'user_002',
      name: 'Priya Sharma',
      email: 'priya@stockiq.com',
      role: UserRole.manager,
      createdAt: DateTime(2024, 2, 5),
    ),
    AppUser(
      id: 'user_003',
      name: 'Arun Mehta',
      email: 'arun@stockiq.com',
      role: UserRole.worker,
      createdAt: DateTime(2024, 3, 15),
    ),
  ];

  // ── Suppliers ─────────────────────────────────────────────────────────────
  static final List<Supplier> suppliers = [
    Supplier(
      id: 'sup_001',
      name: 'TechParts India Pvt. Ltd.',
      contactName: 'Vikram Singh',
      email: 'vikram@techparts.in',
      phone: '+91 98765 43210',
      address: '45, Industrial Area Phase 2, Chandigarh - 160002',
      productIds: ['prod_001', 'prod_002', 'prod_003'],
      createdAt: DateTime(2024, 1, 15),
    ),
    Supplier(
      id: 'sup_002',
      name: 'GlobalMachinery Co.',
      contactName: 'Sonia Patel',
      email: 'sonia@globalmachinery.com',
      phone: '+91 87654 32109',
      address: '12, MIDC Phase 5, Pune - 411057',
      productIds: ['prod_004', 'prod_005'],
      createdAt: DateTime(2024, 2, 10),
    ),
    Supplier(
      id: 'sup_003',
      name: 'FastBolt Suppliers',
      contactName: 'Ravi Gupta',
      email: 'ravi@fastbolt.in',
      phone: '+91 76543 21098',
      address: '78, G.T. Road, Ludhiana - 141001',
      productIds: ['prod_006', 'prod_007'],
      createdAt: DateTime(2024, 3, 5),
    ),
    Supplier(
      id: 'sup_004',
      name: 'ChemBase Exports',
      contactName: 'Anita Joshi',
      email: 'anita@chembase.com',
      phone: '+91 65432 10987',
      address: '33, Chemical Zone, Vapi - 396195',
      productIds: ['prod_008', 'prod_009', 'prod_010'],
      createdAt: DateTime(2024, 4, 1),
    ),
  ];

  // ── Products ──────────────────────────────────────────────────────────────
  static final List<Product> products = [
    Product(
      id: 'prod_001',
      name: 'Industrial Motor Bearing 6205',
      sku: 'BRG-6205-ZZ',
      category: 'Bearings',
      quantity: 245,
      threshold: 50,
      supplierId: 'sup_001',
      price: 285.00,
      costPrice: 210.00,
      unit: 'pcs',
      updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
      createdAt: DateTime(2024, 1, 20),
    ),
    Product(
      id: 'prod_002',
      name: 'Stainless Steel Hex Bolt M12',
      sku: 'BOLT-SS-M12',
      category: 'Fasteners',
      quantity: 8,
      threshold: 100,
      supplierId: 'sup_001',
      price: 12.50,
      costPrice: 8.00,
      unit: 'pcs',
      updatedAt: DateTime.now().subtract(const Duration(hours: 6)),
      createdAt: DateTime(2024, 1, 25),
    ),
    Product(
      id: 'prod_003',
      name: 'PVC Insulation Tape (20m)',
      sku: 'TAPE-PVC-20M',
      category: 'Electrical',
      quantity: 0,
      threshold: 30,
      supplierId: 'sup_001',
      price: 45.00,
      costPrice: 28.00,
      unit: 'rolls',
      updatedAt: DateTime.now().subtract(const Duration(days: 1)),
      createdAt: DateTime(2024, 2, 5),
    ),
    Product(
      id: 'prod_004',
      name: 'Hydraulic Oil 68 Grade (5L)',
      sku: 'OIL-HYD-68-5L',
      category: 'Lubricants',
      quantity: 42,
      threshold: 20,
      supplierId: 'sup_002',
      price: 890.00,
      costPrice: 650.00,
      unit: 'cans',
      updatedAt: DateTime.now().subtract(const Duration(hours: 12)),
      createdAt: DateTime(2024, 2, 10),
    ),
    Product(
      id: 'prod_005',
      name: 'V-Belt Drive A42',
      sku: 'BELT-VD-A42',
      category: 'Drive Systems',
      quantity: 18,
      threshold: 15,
      supplierId: 'sup_002',
      price: 340.00,
      costPrice: 240.00,
      unit: 'pcs',
      updatedAt: DateTime.now().subtract(const Duration(hours: 4)),
      createdAt: DateTime(2024, 2, 18),
    ),
    Product(
      id: 'prod_006',
      name: 'GI Wire 8 SWG (5kg coil)',
      sku: 'WIRE-GI-8SWG',
      category: 'Wire & Cable',
      quantity: 135,
      threshold: 25,
      supplierId: 'sup_003',
      price: 560.00,
      costPrice: 420.00,
      unit: 'coils',
      updatedAt: DateTime.now().subtract(const Duration(hours: 18)),
      createdAt: DateTime(2024, 3, 8),
    ),
    Product(
      id: 'prod_007',
      name: 'Circlip Pliers Set (5pc)',
      sku: 'PLIER-CLP-5PC',
      category: 'Tools',
      quantity: 6,
      threshold: 10,
      supplierId: 'sup_003',
      price: 1250.00,
      costPrice: 900.00,
      unit: 'sets',
      updatedAt: DateTime.now().subtract(const Duration(days: 3)),
      createdAt: DateTime(2024, 3, 12),
    ),
    Product(
      id: 'prod_008',
      name: 'Solvent Cleaner (1L)',
      sku: 'SOLV-CLN-1L',
      category: 'Chemicals',
      quantity: 78,
      threshold: 20,
      supplierId: 'sup_004',
      price: 185.00,
      costPrice: 130.00,
      unit: 'bottles',
      updatedAt: DateTime.now().subtract(const Duration(days: 2)),
      createdAt: DateTime(2024, 4, 3),
    ),
    Product(
      id: 'prod_009',
      name: 'Gasket Sheet 3mm (1m x 1m)',
      sku: 'GSKT-3MM-1X1',
      category: 'Seals & Gaskets',
      quantity: 3,
      threshold: 15,
      supplierId: 'sup_004',
      price: 720.00,
      costPrice: 520.00,
      unit: 'sheets',
      updatedAt: DateTime.now().subtract(const Duration(hours: 8)),
      createdAt: DateTime(2024, 4, 10),
    ),
    Product(
      id: 'prod_010',
      name: 'Anti-Vibration Mount M8 (Pack of 4)',
      sku: 'AVM-M8-PK4',
      category: 'Vibration Control',
      quantity: 55,
      threshold: 10,
      supplierId: 'sup_004',
      price: 460.00,
      costPrice: 320.00,
      unit: 'packs',
      updatedAt: DateTime.now().subtract(const Duration(days: 45)), // dead stock
      createdAt: DateTime(2024, 4, 15),
    ),
  ];

  // ── Transactions ──────────────────────────────────────────────────────────
  static final List<Transaction> transactions = _buildTransactions();

  static List<Transaction> _buildTransactions() {
    final now = DateTime.now();
    final txns = <Transaction>[];
    var counter = 1;

    String tid() => 'txn_${(counter++).toString().padLeft(4, '0')}';

    // prod_001 — Bearing (healthy stock, moderate movement)
    for (var d = 29; d >= 0; d--) {
      if (d % 3 == 0) {
        txns.add(Transaction(
          id: tid(),
          productId: 'prod_001',
          userId: 'user_003',
          type: TransactionType.stockOut,
          quantity: 8 + (d % 4),
          timestamp: now.subtract(Duration(days: d, hours: 10)),
        ));
      }
      if (d % 10 == 0) {
        txns.add(Transaction(
          id: tid(),
          productId: 'prod_001',
          userId: 'user_001',
          type: TransactionType.stockIn,
          quantity: 100,
          notes: 'Bulk restock from TechParts',
          timestamp: now.subtract(Duration(days: d, hours: 8)),
        ));
      }
    }

    // prod_002 — Bolt (very low stock, fast-moving)
    for (var d = 29; d >= 0; d--) {
      if (d % 2 == 0) {
        txns.add(Transaction(
          id: tid(),
          productId: 'prod_002',
          userId: 'user_003',
          type: TransactionType.stockOut,
          quantity: 20 + (d % 10),
          timestamp: now.subtract(Duration(days: d, hours: 11)),
        ));
      }
    }
    txns.add(Transaction(
      id: tid(),
      productId: 'prod_002',
      userId: 'user_001',
      type: TransactionType.stockIn,
      quantity: 500,
      notes: 'Emergency restock',
      timestamp: now.subtract(const Duration(days: 25)),
    ));

    // prod_003 — PVC Tape (out of stock)
    for (var d = 20; d >= 10; d--) {
      txns.add(Transaction(
        id: tid(),
        productId: 'prod_003',
        userId: 'user_003',
        type: TransactionType.stockOut,
        quantity: 5,
        timestamp: now.subtract(Duration(days: d)),
      ));
    }

    // prod_004 — Hydraulic Oil (healthy)
    for (var d = 29; d >= 0; d -= 4) {
      txns.add(Transaction(
        id: tid(),
        productId: 'prod_004',
        userId: 'user_003',
        type: TransactionType.stockOut,
        quantity: 3,
        timestamp: now.subtract(Duration(days: d)),
      ));
    }

    // prod_005 — V-Belt (low stock, daily usage)
    for (var d = 29; d >= 0; d--) {
      txns.add(Transaction(
        id: tid(),
        productId: 'prod_005',
        userId: 'user_003',
        type: TransactionType.stockOut,
        quantity: 2,
        timestamp: now.subtract(Duration(days: d, hours: 9)),
      ));
    }
    txns.add(Transaction(
      id: tid(),
      productId: 'prod_005',
      userId: 'user_001',
      type: TransactionType.stockIn,
      quantity: 50,
      timestamp: now.subtract(const Duration(days: 28)),
    ));

    // prod_006 — GI Wire (good stock)
    for (var d = 29; d >= 0; d -= 5) {
      txns.add(Transaction(
        id: tid(),
        productId: 'prod_006',
        userId: 'user_003',
        type: TransactionType.stockOut,
        quantity: 10,
        timestamp: now.subtract(Duration(days: d)),
      ));
    }

    // prod_007 — Circlip Pliers (low stock, slow mover)
    for (var d = 29; d >= 0; d -= 7) {
      txns.add(Transaction(
        id: tid(),
        productId: 'prod_007',
        userId: 'user_003',
        type: TransactionType.stockOut,
        quantity: 1,
        timestamp: now.subtract(Duration(days: d)),
      ));
    }

    // prod_009 — Gasket Sheet (critically low)
    for (var d = 14; d >= 0; d--) {
      txns.add(Transaction(
        id: tid(),
        productId: 'prod_009',
        userId: 'user_003',
        type: TransactionType.stockOut,
        quantity: 2,
        timestamp: now.subtract(Duration(days: d)),
      ));
    }

    // prod_010 — Anti-Vibration Mount (dead stock — no recent OUT)
    txns.add(Transaction(
      id: tid(),
      productId: 'prod_010',
      userId: 'user_001',
      type: TransactionType.stockIn,
      quantity: 60,
      notes: 'Initial stock',
      timestamp: now.subtract(const Duration(days: 60)),
    ));
    txns.add(Transaction(
      id: tid(),
      productId: 'prod_010',
      userId: 'user_003',
      type: TransactionType.stockOut,
      quantity: 5,
      timestamp: now.subtract(const Duration(days: 48)),
    ));

    return txns;
  }

  // ── Helper: Transactions by product ───────────────────────────────────────
  static Map<String, List<Transaction>> get transactionsByProduct {
    final map = <String, List<Transaction>>{};
    for (final t in transactions) {
      map.putIfAbsent(t.productId, () => []).add(t);
    }
    return map;
  }
}
