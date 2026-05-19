import 'package:intl/intl.dart';

class AppFormatters {
  static String formatCurrency(double amount) {
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    ).format(amount);
  }

  static String formatDate(DateTime date) {
    return DateFormat('MMM d, yyyy').format(date);
  }

  static String formatDateTime(DateTime date) {
    return DateFormat('MMM d, h:mm a').format(date);
  }

  static String formatCompactNumber(int number) {
    return NumberFormat.compact().format(number);
  }

  static String formatQuantity(int totalPcs, int? pcsPerCarton) {
    final size = pcsPerCarton ?? 1;
    if (size <= 1) return '$totalPcs pcs';
    final cartons = totalPcs ~/ size;
    final pcs = totalPcs % size;
    if (cartons == 0) return '$pcs pcs';
    if (pcs == 0) return '$cartons ctn';
    return '$cartons ctn, $pcs pcs';
  }
}
