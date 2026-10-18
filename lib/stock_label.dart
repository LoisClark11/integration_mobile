import 'package:flutter/material.dart';

/// Reads a `products.stock` value.
///
/// Returns null when the column is missing, which happens on a database
/// that has not run the stock migration yet. Callers treat null as
/// "unknown" and hide the badge rather than claiming a number.
int? readStock(dynamic rawStock) {
  if (rawStock == null) return null;

  if (rawStock is num) return rawStock.toInt();

  return int.tryParse(rawStock.toString());
}

/// How many units are treated as "running low".
const int kLowStockThreshold = 5;

/// The wording and the colour, shared by both widgets below so the grid
/// card and the product page can never describe the same number
/// differently.
class StockTone {
  const StockTone(this.text, this.color);

  final String text;
  final Color color;

  factory StockTone.of(int? stock) {
    if (stock == null) {
      return const StockTone("", Color(0xFF2E7D32));
    }

    if (stock <= 0) {
      return const StockTone("Out of stock", Color(0xFFD32F2F));
    }

    if (stock <= kLowStockThreshold) {
      return StockTone("Only $stock left", const Color(0xFFEF6C00));
    }

    return StockTone("$stock in stock", const Color(0xFF2E7D32));
  }
}

/// The stock line drawn under a product name.
///
/// Reads the same way in every place it appears:
///
///   0        Out of stock
///   1..5     Only N left
///   6+       N in stock
///
/// A null [stock] draws nothing at all, so a product on a database
/// without the column looks unchanged rather than claiming zero.
class StockLabel extends StatelessWidget {
  const StockLabel({
    super.key,
    required this.stock,
    this.textStyle,
    this.showIcon = false,
  });

  final int? stock;

  /// Overrides the default style, for callers that need a different
  /// size or weight.
  final TextStyle? textStyle;

  final bool showIcon;

  bool get isOutOfStock => stock != null && stock! <= 0;

  bool get isLow => stock != null && stock! > 0 && stock! <= kLowStockThreshold;

  @override
  Widget build(BuildContext context) {
    if (stock == null) return const SizedBox.shrink();

    final tone = StockTone.of(stock);

    final style = textStyle ??
        const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        );

    return Row(
      mainAxisSize: MainAxisSize.min,

      children: [
        if (showIcon) ...[
          Icon(
            isOutOfStock
                ? Icons.remove_circle_outline
                : Icons.inventory_2_outlined,
            size: (style.fontSize ?? 12) + 2,
            color: tone.color,
          ),

          const SizedBox(width: 4),
        ],

        Text(
          tone.text,
          style: style.copyWith(color: tone.color),
        ),
      ],
    );
  }
}

/// Stock as a pill laid over the product photo.
///
/// Used on the grid card, which is a fixed aspect ratio cell: its text
/// block is unbounded, so an extra line there pushes the price off the
/// bottom. Overlaying the photo costs no height at all and leaves the
/// description its two lines.
class StockBadge extends StatelessWidget {
  const StockBadge({
    super.key,
    required this.stock,
  });

  final int? stock;

  @override
  Widget build(BuildContext context) {
    if (stock == null) return const SizedBox.shrink();

    final tone = StockTone.of(stock);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 3,
      ),

      decoration: BoxDecoration(
        color: tone.color,
        borderRadius: BorderRadius.circular(20),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),

      child: Text(
        tone.text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          height: 1.3,
        ),
      ),
    );
  }
}