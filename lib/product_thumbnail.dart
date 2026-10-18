import 'package:flutter/material.dart';

import 'product_image.dart';

/// The image block that sits at the top of a product card.
///
/// This exists so the banner carousel can show the item picture exactly
/// the way the product grid does. The two sit on the same screen, so a
/// second hand-rolled version of this styling is immediately visible as
/// an inconsistency -- one photo cropped differently, or sitting on a
/// different background colour, right beside the other.
///
/// [ProductImage] underneath still owns the remote/asset/placeholder
/// fallback, so a missing upload never breaks the layout.
class ProductThumbnail extends StatelessWidget {
  const ProductThumbnail({
    super.key,
    required this.rawImage,
    this.height = 140,
    this.width,
    this.borderRadius = const BorderRadius.vertical(
      top: Radius.circular(20),
    ),
    this.backgroundColor = const Color(0xFFFCEBEF),
    this.fit = BoxFit.cover,
  });

  /// The `image_url` field of the product row, or of the slide.
  final dynamic rawImage;

  /// Height of the block. The grid cards use the default.
  final double height;

  /// Width of the block. Null stretches to the parent, which is what the
  /// grid cards want; the carousel passes a fixed square instead.
  final double? width;

  /// Defaults to the card's rounded top corners. The carousel passes a
  /// fully rounded square because its picture stands alone rather than
  /// sitting above text inside a card.
  final BorderRadius borderRadius;

  /// Pale blue backing, shown while the photo loads and wherever the
  /// photo does not fill the block.
  final Color backgroundColor;

  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: Container(
        height: height,
        width: width ?? double.infinity,
        color: backgroundColor,
        child: ProductImage(
          rawImage: rawImage,
          fit: fit,
        ),
      ),
    );
  }
}