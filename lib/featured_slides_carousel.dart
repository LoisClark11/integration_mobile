import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'currency_format.dart';
import 'featured_slide.dart';
import 'product_detail_screen.dart';
import 'product_image.dart';

/// Edge to edge banner carousel that sits above the product grid.
///
/// Each slide uploads one wide picture, `banner_url`, which fills the
/// slide from edge to edge so the row reads as a banner rather than
/// another product card. The advertised item is a real catalog product;
/// when the slide leaves copy or its banner blank, values fall back to
/// that product, and tapping the slide opens the linked product.
///
/// Slides advance by themselves, respond to a swipe, and show dot
/// indicators.
class FeaturedSlidesCarousel extends StatefulWidget {
  const FeaturedSlidesCarousel({
    super.key,
    required this.slides,
    this.productsById = const {},
  });

  /// Rows from the `featured_slides` table, in carousel order.
  final List<Map<String, dynamic>> slides;

  /// Catalog rows keyed by id, used to fill in item name, price and
  /// banner fallbacks for slides that left those fields blank. Provided
  /// by the parent so the screen keeps a single products subscription.
  final Map<String, Map<String, dynamic>> productsById;

  /// Height of the banner band for the current screen width.
  ///
  /// Wide banners are the norm on desktop, but an uncapped ratio turns
  /// into a letterbox slot on a monitor, so the height is clamped. The
  /// method is public so a loading placeholder can reserve exactly the
  /// same space and the grid below does not jump once the slides land.
  ///
  /// The lower clamp is set by the copy, not the picture. Headline,
  /// subtitle, item name, price and button stacked together need a
  /// little over 200 logical pixels once the item name is its own line,
  /// and below that they collide with the dot indicators.
  static double bannerHeightFor(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return math.min(math.max(width * 0.62, 224.0), 330.0);
  }

  @override
  State<FeaturedSlidesCarousel> createState() =>
      _FeaturedSlidesCarouselState();
}

class _FeaturedSlidesCarouselState extends State<FeaturedSlidesCarousel> {
  /// Long enough to read the headline and the button, short enough that
  /// a shopper is not waiting to see the next offer.
  static const Duration _autoAdvanceInterval = Duration(seconds: 5);

  static const Duration _slideTransition = Duration(milliseconds: 420);

  /// Arrows are drawn only once the slide is this wide, which is where
  /// there is room for them beside the copy and the item picture.
  static const double _arrowsBreakpoint = 560;

  /// Edge space the arrow buttons take up on the right, gap included.
  ///
  /// The slide reserves exactly this much padding while the arrows are
  /// on screen, otherwise the buttons sit on top of the item picture.
  static const double _arrowsFootprint = 90;

  final PageController _controller = PageController();

  /// Slides with blank fields already resolved, so the build methods
  /// never have to think about missing values.
  List<FeaturedSlide> _slides = const [];

  /// Raw slide rows, kept so the resolved list can be rebuilt when the
  /// catalog lookup below brings in new data.
  List<Map<String, dynamic>> _rows = const [];

  int _currentIndex = 0;

  Timer? _autoAdvanceTimer;

  @override
  void initState() {
    super.initState();

    _rows = widget.slides;
    _rebuildSlides();
    _restartAutoAdvance();
  }

  @override
  void didUpdateWidget(FeaturedSlidesCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);

    // The admin can add, edit or deactivate a slide while the page is
    // open, because the list is a realtime subscription. Product data is
    // owned by the parent and passed in so the screen keeps a single
    // catalog subscription.
    if (oldWidget.slides != widget.slides ||
        oldWidget.productsById != widget.productsById) {
      _rows = widget.slides;
      _rebuildSlides();
      _restartAutoAdvance();
    }
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Recomputes [_slides] from the current rows and catalog, then keeps
  /// [_currentIndex] pointing at something real.
  void _rebuildSlides() {
    _slides = _rows
        .map((row) => FeaturedSlide.fromRow(row, widget.productsById))
        .where((slide) => slide.isRenderable)
        .toList();

    final lastIndex = math.max(_slides.length - 1, 0);

    if (_currentIndex <= lastIndex) return;

    _currentIndex = lastIndex;

    // The slide that was on screen was just deactivated or deleted, so
    // the viewport has to be parked on a page that still exists. Done
    // after the frame, because the controller can only move once the
    // shorter list has been laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;

      _controller.jumpToPage(_currentIndex);
    });
  }

  void _restartAutoAdvance() {
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = null;

    if (_slides.length < 2) return;

    _autoAdvanceTimer = Timer.periodic(_autoAdvanceInterval, (_) {
      _step(1);
    });
  }

  /// Moves the carousel by whole slides, wrapping around at either end.
  void _step(int delta) {
    if (_slides.length < 2) return;

    _restartAutoAdvance();

    _goToPage((_currentIndex + delta) % _slides.length);
  }

  void _goToPage(int index) {
    if (!_controller.hasClients) return;
    if (_slides.isEmpty) return;

    _controller.animateToPage(
      index.clamp(0, _slides.length - 1),
      duration: _slideTransition,
      curve: Curves.easeOutCubic,
    );
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });

    // Restarting the timer after every move gives a consistent full
    // dwell time, rather than letting a slide that was already half way
    // through its five seconds leave after half a second.
    _restartAutoAdvance();
  }

  /// Pauses the auto advance while a finger or trackpad is dragging.
  bool _onScrollNotification(ScrollNotification notification) {
    // Only a real drag counts. The auto advance and the arrow buttons
    // also emit scroll notifications, and reacting to those would
    // restart the timer twice.
    //
    // `dragDetails` lives on the start and end notifications rather than
    // on the base class, so it is read inside each type check where
    // Dart has promoted the notification to that type.
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _autoAdvanceTimer?.cancel();
      _autoAdvanceTimer = null;
    }

    if (notification is ScrollEndNotification &&
        notification.dragDetails != null) {
      _restartAutoAdvance();
    }

    // Returning false keeps the default scrolling behaviour.
    return false;
  }

  /// Opens the linked product.
  ///
  /// The product page shows the catalog photo, which is the same picture
  /// a slide falls back to for its banner. There is no second upload to
  /// carry over, so nothing is overridden and nothing is written.
  void _openProduct(FeaturedSlide slide) {
    final productId = slide.productId;

    if (productId == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductDetailScreen(
          productId: productId,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Banner
  // ---------------------------------------------------------------------

  Widget _buildBanner(FeaturedSlide slide) {
    // Without a banner the slide falls back to a gradient, so a missing
    // upload degrades to a readable card rather than a broken image.
    final bannerUrl = slide.bannerUrl;

    if (bannerUrl == null) {
      return const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFC25E7A), Color(0xFFF0A6B8)],
          ),
        ),
      );
    }

    return ProductImage(
      rawImage: bannerUrl,
      fit: BoxFit.cover,
    );
  }

  Widget _buildScrims() {
    return const Positioned.fill(
      child: Stack(
        children: [
          // Darkens the left half so the headline stays readable over a
          // bright or busy banner.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xD9000000),
                  Color(0x40000000),
                  Color(0x00000000),
                ],
                stops: [0.0, 0.5, 0.9],
              ),
            ),
          ),

          // Extra shade along the bottom edge for the dot indicators.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x1A000000),
                  Color(0x00000000),
                  Color(0x8A000000),
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Slide content
  // ---------------------------------------------------------------------

  Widget _buildSlide(
    BuildContext context,
    FeaturedSlide slide,
    double width,
    bool showArrows,
  ) {
    final hasProduct = slide.productId != null;

    return Semantics(
      button: hasProduct,
      label: slide.accessibilityLabel,

      child: GestureDetector(
        onTap: hasProduct ? () => _openProduct(slide) : null,

        child: Stack(
          fit: StackFit.expand,

          children: [
            _buildBanner(slide),

            _buildScrims(),

            Padding(
              // The extra right padding hands the arrows their own
              // column instead of letting them cover the copy. The
              // bottom padding keeps the copy clear of the dots.
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                showArrows ? 20 + _arrowsFootprint : 20,
                28,
              ),

              // The banner is the whole slide. The item picture is not
              // drawn here: it is what the customer lands on after
              // tapping through to the product.
              child: Stack(
                children: [
                  // Copy sits top left. The extra bottom padding keeps a
                  // long subtitle clear of the price and button below.
                  Padding(
                    padding: const EdgeInsets.only(bottom: 48),
                    child: _buildCopy(slide, width),
                  ),

                  // Price and button sit in the bottom right corner of
                  // the picture, so the artwork across the middle and
                  // left of the banner stays unobstructed.
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: _buildPriceAndButton(slide, width),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Everything scales with the slide so the layout holds up from a
  // small phone to a wide desktop window.
  static double _headlineSizeFor(double width) =>
      math.min(math.max(width * 0.055, 15.0), 26.0).toDouble();

  static double _supportingSizeFor(double width) =>
      math.min(math.max(width * 0.032, 11.0), 15.0).toDouble();

  static double _detailSizeFor(double width) =>
      math.min(math.max(width * 0.030, 11.0), 14.0).toDouble();

  static double _priceSizeFor(double width) =>
      math.min(math.max(width * 0.036, 12.0), 17.0).toDouble();

  Widget _buildCopy(FeaturedSlide slide, double width) {
    final headlineSize = _headlineSizeFor(width);

    final supportingSize = _supportingSizeFor(width);

    final detailSize = _detailSizeFor(width);

    final shadows = <Shadow>[
      const Shadow(
        color: Color(0x99000000),
        blurRadius: 10,
        offset: Offset(0, 2),
      ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,

      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        _buildBadge(),

        const SizedBox(height: 8),

        // Headline. The subtitle and the item name are separate lines
        // rather than being folded into this one, so the admin controls
        // each field independently.
        Text(
          slide.title ?? "Featured",
          maxLines: 2,
          overflow: TextOverflow.ellipsis,

          style: TextStyle(
            color: Colors.white,
            fontSize: headlineSize,
            fontWeight: FontWeight.bold,
            height: 1.15,
            shadows: shadows,
          ),
        ),

        if (slide.subtitle != null) ...[
          const SizedBox(height: 4),

          Text(
            slide.subtitle!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,

            style: TextStyle(
              color: Colors.white,
              fontSize: supportingSize,
              height: 1.3,
              shadows: shadows,
            ),
          ),
        ],

        // Item name. This is the admin's override: it replaces the
        // product's own name on the banner, and falls back to that name
        // when the admin left it blank.
        if (slide.itemName != null) ...[
          const SizedBox(height: 8),

          Text(
            slide.itemName!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,

            style: TextStyle(
              color: Colors.white,
              fontSize: detailSize,
              fontWeight: FontWeight.w600,
              height: 1.2,
              shadows: shadows,
            ),
          ),
        ],

      ],
    );
  }

  /// The price pill and order button, pinned to the bottom right of
  /// the banner picture so they never sit on top of the artwork.
  ///
  /// Both sides stay flexible on purpose. A price such as
  /// "PHP 12,999.00" next to a long button label easily exceeds the
  /// room left on a narrow phone, and an unbounded Row would draw past
  /// the edge. Each side takes what it needs and ellipsises the rest,
  /// which costs a few characters rather than the whole banner.
  Widget _buildPriceAndButton(FeaturedSlide slide, double width) {
    if (slide.itemPrice == null && slide.productId == null) {
      return const SizedBox.shrink();
    }

    final shadows = <Shadow>[
      const Shadow(
        color: Color(0x99000000),
        blurRadius: 10,
        offset: Offset(0, 2),
      ),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,

      children: [
        if (slide.itemPrice != null)
          Flexible(
            child: Text(
              CurrencyFormat.php(slide.itemPrice!),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,

              style: TextStyle(
                color: Colors.white,
                fontSize: _priceSizeFor(width),
                fontWeight: FontWeight.bold,
                shadows: shadows,
              ),
            ),
          ),

        if (slide.itemPrice != null && slide.productId != null)
          const SizedBox(width: 12),

        if (slide.productId != null)
          Flexible(
            child: _buildButton(slide, _supportingSizeFor(width)),
          ),
      ],
    );
  }

  /// Small "Featured" pill that marks the row as promotional.
  Widget _buildBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 4,
      ),

      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.35),
        ),
      ),

      child: const Row(
        mainAxisSize: MainAxisSize.min,

        children: [
          Icon(
            Icons.auto_awesome_rounded,
            size: 12,
            color: Colors.white,
          ),

          SizedBox(width: 5),

          Text(
            "Featured",
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButton(FeaturedSlide slide, double fontSize) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(30),

      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: () => _openProduct(slide),

        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 8,
          ),

          child: Row(
            mainAxisSize: MainAxisSize.min,

            children: [
              Flexible(
                child: Text(
                  slide.buttonLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,

                  style: TextStyle(
                    color: const Color(0xFFC25E7A),
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const SizedBox(width: 5),

              const Icon(
                Icons.shopping_cart_rounded,
                size: 14,
                color: Color(0xFFC25E7A),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Controls
  // ---------------------------------------------------------------------

  Widget _buildDots() {
    if (_slides.length < 2) return const SizedBox.shrink();

    return Positioned(
      left: 0,
      right: 0,
      bottom: 11,

      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,

        children: [
          for (var index = 0; index < _slides.length; index++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,

              margin: const EdgeInsets.symmetric(horizontal: 3),

              width: index == _currentIndex ? 20 : 7,
              height: 7,

              decoration: BoxDecoration(
                color: index == _currentIndex
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.45),

                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }

  /// Arrow buttons, drawn only when the slide is wide enough to hold
  /// them. On a phone a swipe is the expected gesture and the dots
  /// already show there is more than one slide, so the arrows would only
  /// crowd the item picture.
  Widget _buildArrows() {
    return Positioned(
      right: 12,
      top: 0,
      bottom: 0,

      child: Row(
        mainAxisSize: MainAxisSize.min,

        children: [
          _buildArrowButton(
            Icons.chevron_left_rounded,
            () => _step(-1),
          ),

          const SizedBox(width: 6),

          _buildArrowButton(
            Icons.chevron_right_rounded,
            () => _step(1),
          ),
        ],
      ),
    );
  }

  /// Whether the arrows are on screen for a slide this wide.
  bool _showsArrows(double width) {
    return _slides.length >= 2 && width >= _arrowsBreakpoint;
  }

  Widget _buildArrowButton(IconData icon, VoidCallback onPressed) {
    return Material(
      color: Colors.black.withValues(alpha: 0.32),
      shape: const CircleBorder(),

      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,

        child: SizedBox(
          width: 36,
          height: 36,

          child: Icon(
            icon,
            size: 24,
            color: Colors.white,
          ),
        ),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    // No slides configured yet, so nothing is drawn and the page above
    // the grid is untouched.
    if (_slides.isEmpty) {
      return const SizedBox.shrink();
    }

    final width = MediaQuery.of(context).size.width;

    final showArrows = _showsArrows(width);

    return SizedBox(
      width: double.infinity,
      height: FeaturedSlidesCarousel.bannerHeightFor(context),

      child: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: _onScrollNotification,

            child: PageView.builder(
              controller: _controller,
              onPageChanged: _onPageChanged,

              itemCount: _slides.length,

              itemBuilder: (context, index) {
                return _buildSlide(
                  context,
                  _slides[index],
                  width,
                  showArrows,
                );
              },
            ),
          ),

          if (showArrows) _buildArrows(),

          _buildDots(),
        ],
      ),
    );
  }
}
