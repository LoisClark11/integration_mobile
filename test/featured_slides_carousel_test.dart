import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_mobile/featured_slides_carousel.dart';
import 'package:integration_mobile/product_image.dart';
import 'package:integration_mobile/product_thumbnail.dart';

/// Lays the banner strip out at the screen sizes the app actually runs
/// at and checks nothing overflows.
///
/// No database is involved. Every slide below carries its own fields,
/// and the carousel's optional catalog lookup is built to fail without
/// taking the banners with it.
///
/// The images point at unreachable hosts on purpose. A test image load
/// always fails, `ProductImage` catches it and draws the bundled
/// placeholder, which is the same path a broken upload takes in
/// production.
void main() {
  Map<String, dynamic> slide({
    String id = 'slide-1',
    String? productId = 'product-1',
    String? title = 'Midyear Mega Sale',
    String? subtitle = 'Save up to 50% on selected items this week only',
    String? itemName = 'Wireless Keyboard',
    double? itemPrice = 899,
    String? bannerUrl = 'https://example.com/featured/banner/1.png',
    String buttonLabel = 'Order Now',
  }) {
    return {
      'id': id,
      'product_id': productId,
      'title': title,
      'subtitle': subtitle,
      'item_name': itemName,
      'item_price': itemPrice,
      'banner_url': bannerUrl,
      'button_label': buttonLabel,
    };
  }

  /// Pumps the carousel at a logical screen size and reports any layout
  /// failure. An overflow surfaces as a framework error, which the test
  /// binding records.
  Future<void> pumpCarousel(
    WidgetTester tester, {
    required Size screen,
    required List<Map<String, dynamic>> slides,
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFFFBF6F2),
          body: FeaturedSlidesCarousel(slides: slides),
        ),
      ),
    );

    // Several frames: one to lay out, then enough for the image error
    // handlers and the entry animations to settle.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull);

    // Unmount so the auto advance timer is cancelled. Leaving it
    // running fails the test for a pending timer.
    await tester.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('two slides fit on a small phone', (tester) async {
    await pumpCarousel(
      tester,
      screen: const Size(320, 640),
      slides: [slide(), slide(id: 'slide-2')],
    );
  });

  testWidgets('two slides fit on a typical phone', (tester) async {
    await pumpCarousel(
      tester,
      screen: const Size(400, 800),
      slides: [slide(), slide(id: 'slide-2')],
    );
  });

  testWidgets('three slides fit on a tablet', (tester) async {
    await pumpCarousel(
      tester,
      screen: const Size(834, 1112),
      slides: [
        slide(),
        slide(id: 'slide-2'),
        slide(id: 'slide-3'),
      ],
    );
  });

  testWidgets('three slides fit on a desktop window', (tester) async {
    await pumpCarousel(
      tester,
      screen: const Size(1440, 900),
      slides: [
        slide(),
        slide(id: 'slide-2'),
        slide(id: 'slide-3'),
      ],
    );
  });

  testWidgets('long copy still fits on the narrowest phone', (
    tester,
  ) async {
    await pumpCarousel(
      tester,
      screen: const Size(320, 640),
      slides: [
        slide(
          title:
              'Midyear Mega Sale With An Extremely Long Promotional Headline',
          subtitle:
              'Save up to fifty percent on every selected item in store while '
                  'stocks last, terms and conditions apply',
          itemName: 'Wireless Mechanical Keyboard With Blue Switches',
        ),
      ],
    );
  });

  testWidgets('every field at once fits on the narrowest phone', (
    tester,
  ) async {
    // Headline, subtitle, item name, price and button all filled in is
    // the tallest the copy block ever gets.
    await pumpCarousel(
      tester,
      screen: const Size(320, 640),
      slides: [
        slide(
          title: 'Midyear Mega Sale',
          subtitle: 'Save on selected items this week only',
          itemName: 'Wireless Mechanical Keyboard',
          itemPrice: 128999.5,
          buttonLabel: 'Shop The Collection Now',
        ),
      ],
    );
  });

  testWidgets('every field at once fits on a desktop window', (
    tester,
  ) async {
    await pumpCarousel(
      tester,
      screen: const Size(1440, 900),
      slides: [
        slide(
          title: 'Midyear Mega Sale',
          subtitle: 'Save on selected items this week only',
          itemName: 'Wireless Mechanical Keyboard',
          itemPrice: 128999.5,
          buttonLabel: 'Shop The Collection Now',
        ),
      ],
    );
  });

  testWidgets('the item name override is shown on its own line', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeaturedSlidesCarousel(
            slides: [
              slide(
                title: 'Midyear Mega Sale',
                subtitle: 'Save on selected items',
                itemName: 'Wireless Keyboard',
                itemPrice: 899,
                buttonLabel: 'Shop Now',
              ),
            ],
          ),
        ),
      ),
    );

    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Each field is rendered on its own line rather than being folded
    // into the headline, so the admin controls all five independently.
    expect(find.text('Midyear Mega Sale'), findsOneWidget);
    expect(find.text('Save on selected items'), findsOneWidget);
    expect(find.text('Wireless Keyboard'), findsOneWidget);
    expect(find.text('Shop Now'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('only the banner image is loaded', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeaturedSlidesCarousel(slides: [slide()]),
        ),
      ),
    );

    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // A slide uploads one picture. The item's own photo is not fetched
    // for the banner: the row carries banner_url, and the catalog lookup
    // only fills a gap, so exactly one image should load here.
    expect(find.byType(ProductImage), findsOneWidget);
    expect(find.byType(ProductThumbnail), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the button defaults to Order Now', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // No button_label on the row, so the storefront's own default shows.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeaturedSlidesCarousel(
            slides: [
              {
                'id': 'slide-1',
                'product_id': 'product-1',
                'banner_url': 'https://example.com/featured/banner/1.png',
              },
            ],
          ),
        ),
      ),
    );

    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Order Now'), findsOneWidget);
    expect(find.byIcon(Icons.shopping_cart_rounded), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a slide with no product shows no button', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeaturedSlidesCarousel(
            slides: [
              slide(
                productId: null,
                bannerUrl: 'https://example.com/featured/banner/1.png',
              ),
            ],
          ),
        ),
      ),
    );

    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Nothing to order without a product behind the banner.
    expect(find.text('Order Now'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a slide with no copy at all still lays out', (tester) async {
    // Banner only. Everything else is borrowed or simply absent.
    await pumpCarousel(
      tester,
      screen: const Size(400, 800),
      slides: [slide(title: null, subtitle: null, itemName: null, itemPrice: null)],
    );
  });

  testWidgets('draws nothing when there are no slides', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FeaturedSlidesCarousel(slides: []),
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(PageView), findsNothing);

    // The widget collapses to nothing rather than leaving a gap above
    // the grid, so the header sits directly on the product list.
    expect(
      tester.getSize(find.byType(FeaturedSlidesCarousel)),
      Size.zero,
    );
  });

  testWidgets('shows the headline, price and button of the first slide', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeaturedSlidesCarousel(slides: [slide()]),
        ),
      ),
    );

    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Midyear Mega Sale'), findsOneWidget);
    expect(find.textContaining('PHP'), findsOneWidget);
    expect(find.text('Order Now'), findsOneWidget);
    expect(find.text('Featured'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('price and button sit in the bottom right of the banner', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeaturedSlidesCarousel(slides: [slide()]),
        ),
      ),
    );

    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final banner = tester.getRect(find.byType(FeaturedSlidesCarousel));
    final button = tester.getRect(find.text('Order Now'));
    final price = tester.getRect(find.textContaining('PHP'));

    // Bottom right of the banner: the button in the right half, price
    // and button both in the bottom half, and the price tucked directly
    // beside the button as one right-aligned group. (The price center is
    // not asserted against the banner center -- the test font draws
    // every glyph a full em wide, which inflates the row past the middle
    // even though the group is right anchored.)
    expect(button.center.dx, greaterThan(banner.center.dx));
    expect(button.center.dy, greaterThan(banner.center.dy));
    expect(price.center.dy, greaterThan(banner.center.dy));
    expect(price.right, lessThanOrEqualTo(button.left));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('drops a slide with no banner and no product photo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeaturedSlidesCarousel(
            slides: [
              // No upload, and the catalog lookup is unavailable in a
              // test, so there is genuinely nothing to draw.
              slide(bannerUrl: null, productId: null),
              slide(id: 'slide-2', title: 'Only real slide'),
            ],
          ),
        ),
      ),
    );

    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The empty draft is skipped, so only one dot indicator is drawn.
    expect(find.text('Only real slide'), findsOneWidget);
    expect(find.byType(PageView), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('arrows appear on a wide screen and not on a phone', (
    tester,
  ) async {
    Future<void> pumpAt(Size screen) async {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeaturedSlidesCarousel(
              slides: [slide(), slide(id: 'slide-2')],
            ),
          ),
        ),
      );

      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await pumpAt(const Size(400, 800));
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpAt(const Size(1200, 800));
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a single slide gets no dots and no arrows', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeaturedSlidesCarousel(slides: [slide()]),
        ),
      ),
    );

    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(find.text('Featured'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}