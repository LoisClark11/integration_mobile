/// One featured slide with every blank already resolved.
///
/// A slide uploads exactly one picture:
///
///   `banner_url`  the wide featured picture, which fills the slide
///
/// The item the banner advertises is a real catalog product, and that
/// product already carries its own photo. The slide borrows it, both as
/// a fallback for a missing banner and as the picture on the product
/// page once the customer taps through. Uploading a second picture for
/// the same item would only duplicate what is already there.
///
/// `item_name` and `item_price` are read as overrides for the same
/// reason they are no longer offered in the admin form: a slide saved
/// before those boxes were removed keeps whatever it stored, and a
/// slide that never had them borrows the product's own values.
///
/// The class is public and holds no widgets so the resolution rules can
/// be tested on their own, without a database or a rendered page.
class FeaturedSlide {
  const FeaturedSlide({
    required this.productId,
    required this.bannerUrl,
    required this.title,
    required this.subtitle,
    required this.itemName,
    required this.itemPrice,
    required this.buttonLabel,
  });

  /// Builds a slide from a `featured_slides` row.
  ///
  /// [productsById] is the catalog keyed by id. It is looked up only to
  /// fill in blanks, so an empty map still yields a usable slide for a
  /// row that filled everything in itself.
  factory FeaturedSlide.fromRow(
    Map<String, dynamic> row,
    Map<String, Map<String, dynamic>> productsById,
  ) {
    final productId = _text(row['product_id']);

    // The linked catalog row, which supplies the item's name, price and
    // photo whenever the slide leaves them blank.
    final product = productId == null ? null : productsById[productId];

    return FeaturedSlide(
      productId: productId,

      // The banner falls back to the product photo rather than to
      // nothing, so a slide with no upload still shows a picture.
      bannerUrl:
          _text(row['banner_url']) ?? _text(product?['image_url']),

      title: _text(row['title']),
      subtitle: _text(row['subtitle']),
      itemName: _text(row['item_name']) ?? _text(product?['name']),
      itemPrice:
          _readPrice(row['item_price']) ?? _readPrice(product?['price']),
      buttonLabel: _text(row['button_label']) ?? "Order Now",
    );
  }

  /// Catalog product to open when the slide is tapped, or null when the
  /// slide is a promotion with no product behind it.
  final String? productId;

  final String? bannerUrl;

  final String? title;

  final String? subtitle;

  final String? itemName;

  final double? itemPrice;

  final String buttonLabel;

  /// A slide with nothing to draw would render as an empty block, so it
  /// is dropped and the rest of the carousel carries on.
  bool get isRenderable => bannerUrl != null;

  /// Text read out for screen readers.
  String get accessibilityLabel {
    final parts = <String>[
      ?title,
      ?itemName,
      if (itemPrice != null) "on special offer",
    ];

    return parts.isEmpty
        ? "Featured offer"
        : "Featured offer: ${parts.join(", ")}";
  }

  /// Returns a trimmed string, or null when the field is missing, empty,
  /// or not text. `uuid` columns come back as strings, so a product id
  /// goes through here too.
  static String? _text(dynamic value) {
    if (value == null) return null;

    final text = value.toString().trim();

    return text.isEmpty ? null : text;
  }

  /// `numeric` columns arrive as a double, but a value written as text
  /// by a quick script still has to read.
  static double? _readPrice(dynamic value) {
    if (value == null) return null;

    if (value is num) return value.toDouble();

    return double.tryParse(value.toString());
  }
}