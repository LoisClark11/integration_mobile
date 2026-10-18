import 'package:flutter_test/flutter_test.dart';
import 'package:integration_mobile/featured_slide.dart';

/// Covers the rules that decide what a slide shows when the admin left
/// fields blank, which is the part most likely to surprise someone.
void main() {
  group('FeaturedSlide.fromRow', () {
    const productId = 'product-uuid';

    final products = <String, Map<String, dynamic>>{
      productId: {
        'id': productId,
        'name': 'Desk Lamp',
        'price': 450.0,
        'image_url': 'https://example.com/products/lamp.png',
      },
    };

    test('reads the banner off the row when the admin uploaded one', () {
      final slide = FeaturedSlide.fromRow({
        'product_id': productId,
        'banner_url': 'https://example.com/featured/banner/1.png',
        'item_name': 'Table Lamp',
        'item_price': 499.0,
        'title': 'Spring Sale',
        'subtitle': 'Everything must go',
        'button_label': 'Buy',
      }, products);

      expect(slide.bannerUrl, 'https://example.com/featured/banner/1.png');

      // The row wins over the product, so an admin can advertise a
      // different name or price than the catalog holds.
      expect(slide.itemName, 'Table Lamp');
      expect(slide.itemPrice, 499.0);
      expect(slide.title, 'Spring Sale');
      expect(slide.subtitle, 'Everything must go');
      expect(slide.buttonLabel, 'Buy');
    });

    test('falls back to the product for name, price and photo', () {
      final slide = FeaturedSlide.fromRow({
        'product_id': productId,
        'banner_url': 'https://example.com/featured/banner/1.png',
      }, products);

      // The product already has its own photo, which is the whole reason
      // a slide does not upload a second one.
      expect(slide.bannerUrl, 'https://example.com/featured/banner/1.png');
      expect(slide.itemName, 'Desk Lamp');
      expect(slide.itemPrice, 450.0);
      expect(slide.buttonLabel, 'Order Now');
    });

    test('a slide with no upload borrows the product photo', () {
      final slide = FeaturedSlide.fromRow({
        'product_id': productId,
      }, products);

      expect(slide.bannerUrl, 'https://example.com/products/lamp.png');
      expect(slide.isRenderable, isTrue);
    });

    test('survives a product_id that matches nothing', () {
      // The product was deleted after the slide was saved. The foreign
      // key cascades the slide away, but a stale id must not throw
      // either.
      final slide = FeaturedSlide.fromRow({
        'product_id': 'gone',
        'banner_url': 'https://example.com/featured/banner/1.png',
        'item_name': 'Mystery Item',
      }, products);

      expect(slide.productId, 'gone');
      expect(slide.itemName, 'Mystery Item');
      expect(slide.itemPrice, isNull);
      expect(slide.isRenderable, isTrue);
    });

    test('treats blank and whitespace values as missing', () {
      final slide = FeaturedSlide.fromRow({
        'product_id': '   ',
        'banner_url': '',
        'title': '  ',
      }, const {});

      expect(slide.productId, isNull);
      expect(slide.title, isNull);

      // Nothing to draw, so the carousel drops it.
      expect(slide.isRenderable, isFalse);
    });

    test('is not renderable with no banner and no product photo', () {
      final slide = FeaturedSlide.fromRow({
        'title': 'Draft slide with no uploads yet',
      }, const {});

      expect(slide.title, 'Draft slide with no uploads yet');
      expect(slide.isRenderable, isFalse);
    });

    test('reads a price written as text', () {
      final slide = FeaturedSlide.fromRow({
        'banner_url': 'https://example.com/featured/banner/1.png',
        'item_price': '1234.50',
      }, const {});

      expect(slide.itemPrice, 1234.50);
    });

    test('reads an unparseable price as missing', () {
      final slide = FeaturedSlide.fromRow({
        'banner_url': 'https://example.com/featured/banner/1.png',
        'item_price': 'Ask in store',
      }, const {});

      expect(slide.itemPrice, isNull);
      expect(slide.isRenderable, isTrue);
    });

    test('describes itself for a screen reader', () {
      final slide = FeaturedSlide.fromRow({
        'banner_url': 'https://example.com/featured/banner/1.png',
        'title': 'Spring Sale',
        'item_name': 'Desk Lamp',
        'item_price': 450.0,
      }, const {});

      expect(
        slide.accessibilityLabel,
        'Featured offer: Spring Sale, Desk Lamp, on special offer',
      );
    });
  });
}