import 'package:intl/intl.dart';

/// Shared PHP currency formatting used across the storefront.
///
/// Centralising this keeps the symbol, grouping and decimal places
/// consistent and avoids recreating [NumberFormat] instances in every
/// screen.
class CurrencyFormat {
  CurrencyFormat._();

  static final NumberFormat _php = NumberFormat('#,##0.00');

  /// Formats [amount] as `PHP 1,234.56`.
  static String php(num amount) => 'PHP ${_php.format(amount)}';

  /// Parses a price-like value from a database row or cart snapshot.
  /// Returns 0 when the value is missing or not numeric.
  static double parse(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  /// Parses a quantity/count, clamped to at least 1.
  static int parseQuantity(dynamic value, {int fallback = 1}) {
    final parsed = int.tryParse(value?.toString() ?? '') ?? fallback;
    return parsed < 1 ? 1 : parsed;
  }
}
