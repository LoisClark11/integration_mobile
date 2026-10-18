import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'touchskin_cache.dart';

/// Renders a product image referenced by a database record.
///
/// The admin uploads to Supabase Storage and saves the resulting
/// public URL in `image_url`, so an https link is loaded over the
/// network. Remote pictures go through the shared [TouchSkinCacheManager],
/// so they are downloaded once and served from the phone's disk cache
/// on every later app open. A local asset path still works for
/// bundled artwork, and the placeholder is used when the field is
/// missing, empty, or fails to load, so the layout never breaks.
class ProductImage extends StatelessWidget {
  const ProductImage({
    super.key,
    required this.rawImage,
    this.fit = BoxFit.cover,
  });

  /// Local placeholder used when no usable image is available.
  static const String placeholderAsset =
      'assets/images/product_placeholder.png';

  /// Raw value read from the product's `image_url` field.
  final dynamic rawImage;

  final BoxFit fit;

  /// Returns the field as a trimmed string, or an empty string when
  /// it is missing or not a string.
  String _readValue() {
    if (rawImage == null) return "";

    final value = rawImage is String
        ? rawImage as String
        : rawImage.toString();

    return value.trim();
  }

  Widget _placeholder() {
    return Image.asset(
      placeholderAsset,
      fit: fit,
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = _readValue();

    if (value.isEmpty) {
      return _placeholder();
    }

    final lowerValue = value.toLowerCase();

    // Public URL from Supabase Storage, e.g.
    // https://<project>.supabase.co/storage/v1/object/public/...
    if (lowerValue.startsWith("http://") ||
        lowerValue.startsWith("https://")) {
      return CachedNetworkImage(
        imageUrl: value,
        fit: fit,
        cacheManager: TouchSkinCacheManager.instance,

        // A spinner only shows the very first time a picture is
        // fetched; every later open finds it in the disk cache and
        // paints it instantly.
        placeholder: (context, url) {
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFFC25E7A),
            ),
          );
        },

        errorWidget: (context, url, error) {
          return _placeholder();
        },
      );
    }

    // Local asset path such as `assets/images/laptop.png`.
    return Image.asset(
      value,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        return _placeholder();
      },
    );
  }
}