import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// The app's single image cache.
///
/// Every network picture in TouchSkin loads through
/// [TouchSkinCacheManager.instance], so each image is downloaded once
/// and afterwards read straight from the phone's disk cache: it shows
/// instantly on every later app open and even with no connection.
///
/// The underlying cache manager treats entries as fresh for 7 days by
/// default; a month is a better fit here, because product photos and
/// banners rarely change and re-downloading a full grid on every
/// launch is exactly the cost being removed. Stale entries are
/// refreshed on the next view and old files are evicted automatically
/// once the object limit is hit, so the cache cannot grow forever.
class TouchSkinCacheManager {
  TouchSkinCacheManager._();

  static final CacheManager instance = CacheManager(
    Config(
      'touchskin_image_cache',
      stalePeriod: Duration(days: 30),
      maxNrOfCacheObjects: 500,
    ),
  );
}
