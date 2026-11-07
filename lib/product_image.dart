import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'supabase_service.dart';
import 'touchskin_cache.dart';

/// Renders a product image referenced by a database record.
///
/// The admin uploads to Supabase Storage and saves the resulting
/// public URL in `image_url`, so an https link is loaded over the
/// network. Remote pictures go through the shared [TouchSkinCacheManager],
/// so they are downloaded once and served from the phone's disk cache
/// on every later app open.
///
/// A local asset path still works for bundled artwork. If the field holds a
/// Supabase Storage object path (not a full URL), it is resolved to a
/// public URL for the `product-images` bucket so the photo still loads.
///
/// The placeholder is used when the field is missing, empty, or fails to
/// load, so the layout never breaks.
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
    if (rawImage == null) return '';

    final value = rawImage is String ? rawImage as String : rawImage.toString();

    return value.trim();
  }

  /// Turns a stored Supabase Storage object path into a public URL.
  ///
  /// Some admin flows save only the object path (for example
  /// `featured/banner/123.png` or `product-images/featured/banner/123.png`)
  /// instead of the full public URL. Treating that as a bundled asset
  /// makes it fail and show the placeholder, so we resolve it against the
  /// public bucket here. Known local asset paths (`assets/...`) are left
  /// alone.
  String? _resolveNetworkUrl(String value) {
    final lower = value.toLowerCase();

    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return value;
    }

    // A real bundled asset path; load it with Image.asset.
    if (lower.startsWith('assets/')) {
      return null;
    }

    var objectPath = value.replaceFirst(RegExp(r'^/+'), '');

    // Tolerate values that include the bucket name or the public path
    // prefix without a scheme.
    const bucket = 'product-images';
    const bucketPrefix = '$bucket/';
    if (objectPath.startsWith(bucketPrefix)) {
      objectPath = objectPath.substring(bucketPrefix.length);
    }
    const publicPrefix = 'storage/v1/object/public/$bucket/';
    final publicIndex = objectPath.indexOf(publicPrefix);
    if (publicIndex != -1) {
      objectPath = objectPath.substring(publicIndex + publicPrefix.length);
    }

    if (objectPath.isEmpty) return null;

    final base = SupabaseService.projectUrl.replaceFirst(RegExp(r'/+$'), '');
    return '$base/storage/v1/object/public/$bucket/$objectPath';
  }

  @override
  Widget build(BuildContext context) {
    final value = _readValue();

    if (value.isEmpty) {
      return _Placeholder(fit: fit);
    }

    final networkUrl = _resolveNetworkUrl(value);

    if (networkUrl != null) {
      return _NetworkProductImage(url: networkUrl, fit: fit);
    }

    // Local asset path such as `assets/images/laptop.png`.
    return Image.asset(
      value,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        return _Placeholder(fit: fit);
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.fit});

  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      ProductImage.placeholderAsset,
      fit: fit,
    );
  }
}

/// Network image with a one-time self-heal.
///
/// Remote images are cached for 30 days. If a fetch failed in the past
/// (transient outage, bucket briefly private, bad upload), a stale cached
/// failure can keep showing the placeholder even after the URL works.
/// Evicting the cached entry once and rebuilding gives it a fresh fetch.
class _NetworkProductImage extends StatefulWidget {
  const _NetworkProductImage({required this.url, required this.fit});

  final String url;
  final BoxFit fit;

  @override
  State<_NetworkProductImage> createState() => _NetworkProductImageState();
}

class _NetworkProductImageState extends State<_NetworkProductImage> {
  bool _retried = false;
  int _attempt = 0;

  @override
  void didUpdateWidget(covariant _NetworkProductImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _retried = false;
      _attempt = 0;
    }
  }

  Future<void> _retry() async {
    if (_retried || !mounted) return;
    _retried = true;
    try {
      await TouchSkinCacheManager.instance.removeFile(widget.url);
    } catch (_) {
      // Best effort; still retry the render.
    }
    if (!mounted) return;
    setState(() {
      _attempt += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      key: ValueKey('${widget.url}#$_attempt'),
      imageUrl: widget.url,
      fit: widget.fit,
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
        if (!_retried) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _retry());
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFFC25E7A),
            ),
          );
        }
        return _Placeholder(fit: widget.fit);
      },
    );
  }
}