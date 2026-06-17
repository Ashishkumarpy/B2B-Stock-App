/// Firestore collection names and app-wide constants
class AppConstants {
  AppConstants._();

  // ── Firestore Collections ────────────────────────────────────────────────
  static const String usersCollection = 'users';
  static const String productsCollection = 'products';
  static const String transactionsCollection = 'transactions';
  static const String suppliersCollection = 'suppliers';

  // ── Stock Status Thresholds ──────────────────────────────────────────────
  /// Quantity at or below which item is flagged "Low Stock"
  static const int defaultLowStockThreshold = 10;

  /// Days without any OUT transaction to flag as "Dead Stock"
  static const int deadStockDays = 30;

  /// Lead time in days used for reorder calculation
  static const int defaultLeadTimeDays = 7;

  /// Safety buffer multiplier for reorder quantity
  static const double reorderSafetyBuffer = 1.2;

  // ── Moving Average Window ────────────────────────────────────────────────
  static const int movingAverageDays = 30;

  // ── Hive Box Names ───────────────────────────────────────────────────────
  static const String productsBox = 'products_box';
  static const String transactionsBox = 'transactions_box';
  static const String settingsBox = 'settings_box';
  static const String darkModeKey = 'dark_mode_enabled';

  // ── UI ───────────────────────────────────────────────────────────────────
  static const String appName = 'Zentory';
  static const String appTagline = 'Smart B2B Inventory';

  // ── Pagination ──────────────────────────────────────────────────────────
  static const int pageSize = 20;
}

/// User roles in the system
enum UserRole {
  admin,
  manager,
  worker,
  customer;

  String get label => switch (this) {
        UserRole.admin => 'Admin',
        UserRole.manager => 'Manager',
        UserRole.worker => 'Worker',
        UserRole.customer => 'Customer',
      };

  bool get canManageUsers => this == UserRole.admin || this == UserRole.manager;
  bool get canManageProducts => this == UserRole.admin;
  bool get canManageWarehouses => this == UserRole.admin;
  bool get canViewAnalytics =>
      this != UserRole.worker && this != UserRole.customer;
  bool get canViewWorkerActivity =>
      this == UserRole.admin || this == UserRole.manager;
  bool get canViewStockActivity =>
      this == UserRole.admin ||
      this == UserRole.manager ||
      this == UserRole.worker;
  bool get canRecordStock =>
      this == UserRole.admin ||
      this == UserRole.manager ||
      this == UserRole.worker;
  bool get canManageSuppliers => this == UserRole.admin;
}

/// Stock status derived from quantity vs threshold
enum StockStatus {
  inStock,
  lowStock,
  outOfStock;

  String get label => switch (this) {
        StockStatus.inStock => 'In Stock',
        StockStatus.lowStock => 'Low Stock',
        StockStatus.outOfStock => 'Out of Stock',
      };
}

/// Transaction direction
enum TransactionType {
  stockIn,
  stockOut,
  shift;

  String get label => switch (this) {
        TransactionType.stockIn => 'Stock In',
        TransactionType.stockOut => 'Stock Out',
        TransactionType.shift => 'Shift',
      };

  String get firestoreValue => switch (this) {
        TransactionType.stockIn => 'IN',
        TransactionType.stockOut => 'OUT',
        TransactionType.shift => 'SHIFT',
      };

  static TransactionType fromString(String value) {
    final normalized =
        value.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
    if (normalized == 'in' ||
        normalized == 'stock_in' ||
        normalized == 'stockin') {
      return TransactionType.stockIn;
    }
    if (normalized == 'out' ||
        normalized == 'stock_out' ||
        normalized == 'stockout') {
      return TransactionType.stockOut;
    }
    if (normalized == 'shift' || normalized == 'transfer') {
      return TransactionType.shift;
    }
    return TransactionType.stockOut;
  }
}

/// Stock measurement units
enum StockUnit {
  pieces,
  kilograms,
  liters,
  meters,
  boxes;

  String get label => switch (this) {
        StockUnit.pieces => 'pcs',
        StockUnit.kilograms => 'kg',
        StockUnit.liters => 'L',
        StockUnit.meters => 'm',
        StockUnit.boxes => 'boxes',
      };
}
