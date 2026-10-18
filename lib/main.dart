import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_screen.dart';
import 'reset_password_screen.dart';
import 'cart_screen.dart';
import 'supabase_service.dart';
import 'app_repository.dart';
import 'session.dart';
import 'gradient_header.dart';
import 'app_footer.dart';
import 'user_profile_screen.dart';
import 'product_detail_screen.dart';
import 'product_thumbnail.dart';
import 'stock_label.dart';
import 'featured_slides_carousel.dart';
import 'product_categories.dart';
import 'splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Dark status bar icons are the app-wide default, because the
  // pages themselves are cream and the clock has to stay readable
  // over them once the rose header scrolls away. Every GradientHeader
  // declares white icons for as long as it sits under the status bar
  // (see gradient_header.dart), and so does the splash screen.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  await SupabaseService.initialize();

  runApp(const ProductInventoryApp());
}

/// Lets the auth listener navigate and show messages even though it
/// sits above the Navigator, where a local context cannot reach them.
final GlobalKey<NavigatorState> navigatorKey =
    GlobalKey<NavigatorState>();

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// TouchSkin's brand color -- soft blush, the app-wide accent that
/// replaced the old stock Material blue.
///
/// A full [MaterialColor] rather than a lone [Color]: anything that
/// asks the theme for a shade (text selection, default buttons,
/// ripples) gets a rose tint instead of blue.
const MaterialColor kTouchSkin = MaterialColor(
  0xFFC25E7A,
  <int, Color>{
    50: Color(0xFFFCEBEF),
    100: Color(0xFFF8D7E0),
    200: Color(0xFFF2B3C2),
    300: Color(0xFFEC90A6),
    400: Color(0xFFE77691),
    500: Color(0xFFC25E7A),
    600: Color(0xFFB55670),
    700: Color(0xFF9C4760),
    800: Color(0xFF83394F),
    900: Color(0xFF6A2C3F),
  },
);

class ProductInventoryApp extends StatelessWidget {
  const ProductInventoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TouchSkin',
      theme: ThemeData(primarySwatch: kTouchSkin),

      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,

      // Cold start is always signed out: `persistSession: false` means
      // the session lives only in memory, so there is nothing to restore
      // on a fresh launch. A hot restart can keep the in-memory session
      // for the life of the process, but a real cold start lands on the
      // signed-out products page -- after the splash's short brand
      // moment. The password-reset deep link skips the splash entirely
      // (see onUnknownRoute below) so recovery is never delayed.
      home: const SplashScreen(),

      // Android hands deep links to Flutter as named routes, so the
      // password reset link arrives as "/?code=..." rather than "/".
      // That does not match `home`, and with no routes table Flutter
      // throws and renders a blank screen.
      //
      // Landing on the home screen keeps the link harmless. The real
      // navigation to the new password screen is done by
      // AuthRecoveryListener, which waits for Supabase's
      // passwordRecovery event so a session already exists by the time
      // updateUser runs.
      onUnknownRoute: (settings) {
        return MaterialPageRoute(
          builder: (context) => const DashboardScreen(),
          settings: settings,
        );
      },

      builder: (context, child) {
        return AuthRecoveryListener(
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

/// Listens for the recovery event that fires when the user opens the
/// password reset link, and sends them to the new-password screen.
///
/// This has to sit above the navigator so it works no matter which
/// screen the app happened to be showing when the link arrived.
class AuthRecoveryListener extends StatefulWidget {
  const AuthRecoveryListener({super.key, required this.child});

  final Widget child;

  @override
  State<AuthRecoveryListener> createState() =>
      _AuthRecoveryListenerState();
}

class _AuthRecoveryListenerState extends State<AuthRecoveryListener> {
  StreamSubscription<AuthState>? _subscription;

  /// Guards against showing the screen twice when both the initial
  /// link and a warm deep link report the same recovery.
  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    _subscription = SupabaseService.client.auth.onAuthStateChange.listen(
      _onAuthStateChange,
      onError: _onAuthStreamError,
    );
  }

  /// Turns a failed recovery link into something the user can read
  /// instead of a silent no-op.
  ///
  /// Supabase reports a dead or already used link by pushing an error
  /// onto this same stream, so it is caught here.
  void _onAuthStreamError(Object error, StackTrace stackTrace) {
    final message =
        error is AuthException ? error.message : error.toString();

    final isExpired =
        message.contains('expired') ||
        message.contains('invalid') ||
        message.contains('otp_expired');

    final text = isExpired
        ? "This reset link has expired or was already used. "
            "Please request a new one."
        : "Could not open the reset link. Please try again.";

    // Deferred for the same reason the navigation is.
    Future.delayed(Duration.zero, () {
      scaffoldMessengerKey.currentState
        ?..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(text),
            duration: const Duration(seconds: 5),
          ),
        );
    });
  }

  void _onAuthStateChange(AuthState state) {
    final isRecovery = state.event == AuthChangeEvent.passwordRecovery;

    if (!isRecovery) return;
    if (_navigated) return;

    _navigated = true;

    // Supabase warns that doing other Supabase work inside this
    // callback can deadlock, so the navigation is deferred to the next
    // event loop turn.
    Future.delayed(Duration.zero, () {
      final navigator = navigatorKey.currentState;

      if (navigator == null) {
        _navigated = false;
        return;
      }

      // This listener sits above the Navigator, so a local context
      // cannot reach one. The navigator key is used instead.
      navigator
          .push(
            MaterialPageRoute(
              builder: (context) => const ResetPasswordScreen(),
            ),
          )
          .then((_) {
            _navigated = false;
          })
          .catchError((Object error) {
            _navigated = false;
          });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// Pins the category chip row to the top of the viewport once the
/// customer scrolls past it.
///
/// The row does not pin against the physical top of the screen: the
/// header anchors at y = 0, which is *behind* the system status bar
/// (clock, battery), so the delegate is built [topInset] taller than
/// the row and puts the chips underneath that. The inset reads as an
/// opaque cream band the system icons are drawn on, while the grid
/// slides behind it -- without the band the clock sat right on top
/// of the selected chip. Before pinning, the same band just gives
/// the chips a little more breathing room under the banners.
class _PinnedChipsHeader extends SliverPersistentHeaderDelegate {
  _PinnedChipsHeader({
    required this.child,
    required this.topInset,
  });

  final Widget child;

  /// Distance from the physical top of the screen to the bottom of
  /// the status bar.
  final double topInset;

  static const double _rowHeight = 48;

  @override
  double get minExtent => topInset + _rowHeight;

  @override
  double get maxExtent => topInset + _rowHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      height: minExtent,

      padding: EdgeInsets.only(top: topInset),

      decoration: const BoxDecoration(
        color: Color(0xFFFBF6F2),
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),

      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedChipsHeader oldDelegate) {
    // A fresh delegate with a fresh child is built on every category
    // tap (the selected chip's colours changed), so it must rebuild.
    return oldDelegate.child != child ||
        oldDelegate.topInset != topInset;
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentTabIndex = 0;

  /// The category chip currently selected under the featured banners.
  /// "All Products" is the default and shows the whole catalog.
  String _selectedCategory = kAllProductsCategory;

  /// Attached once in initState and shared by the whole products page,
  /// so the scroll position survives tab switches (IndexedStack keeps
  /// the page alive) and so the footer can follow scroll direction.
  final ScrollController _scrollController = ScrollController();

  /// Previous offset, kept to read direction from -- the footer reacts
  /// to which way the page moves, not to where it is.
  double _lastScrollOffset = 0;

  /// Whether the footer has slid out of view after scrolling down.
  bool _footerHidden = false;

  /// Created once in initState rather than inside build, so the
  /// realtime subscription is not torn down on every rebuild.
  late final Stream<List<Map<String, dynamic>>> _productsStream;

  /// Same rule as above. One subscription per stream, never a new one
  /// built during `build`.
  late final Stream<List<Map<String, dynamic>>> _featuredSlidesStream;

  /// Cached rather than read from `AppSession` during `build`, because
  /// that getter only ever sees the client. Without a listener the
  /// header would keep showing "Log In" after the customer signed in on
  /// the screen behind it.
  bool _isLoggedIn = false;

  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();

    _productsStream = AppRepository.watchProducts();
    _featuredSlidesStream = AppRepository.watchFeaturedSlides();

    // Seeds the button before the first auth event arrives.
    _isLoggedIn = AppSession.isLoggedIn;

    _authSubscription =
        SupabaseService.client.auth.onAuthStateChange.listen((state) {
      final isLoggedIn = state.session != null;

      // Sign in, sign out and logout all land here. Only rebuild when
      // the answer actually changed, so a token refresh mid-session
      // does not churn the page.
      if (isLoggedIn == _isLoggedIn) return;
      if (!mounted) return;

      setState(() {
        _isLoggedIn = isLoggedIn;
      });
    });

    // One listener for the page: it only moves the footer. The header
    // reacts to scroll direction entirely on its own, inside
    // SliverFloatingHeader.
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _authSubscription?.cancel();
    super.dispose();
  }

  /// Hides the footer while the page moves toward the end of the
  /// content and brings it back on any real upward scroll -- the same
  /// reaction the floating header has, driven from the same gesture.
  void _onScroll() {
    if (!mounted || !_scrollController.hasClients) return;

    final delta = _scrollController.offset - _lastScrollOffset;
    _lastScrollOffset = _scrollController.offset;

    // The dead zone keeps ordinary finger jitter from flicking the
    // footer back and forth during one gesture.
    if (delta > 2 && !_footerHidden) {
      setState(() {
        _footerHidden = true;
      });
    } else if (delta < -2 && _footerHidden) {
      setState(() {
        _footerHidden = false;
      });
    }
  }

  void _openLogin() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const LoginScreen(),
      ),
    );
  }

  final NumberFormat _currencyFormatter =
      NumberFormat('#,##0.00');

  String _formatPrice(dynamic price) {
    final parsedPrice =
        double.tryParse(price?.toString() ?? '') ?? 0;

    return 'PHP ${_currencyFormatter.format(parsedPrice)}';
  }

  Future<void> _addToCart(Map<String, dynamic> product) async {
    if (!AppSession.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please log in before adding items to your cart."),
        ),
      );
      return;
    }

    // The button is disabled when this is known, but the cart can also
    // be reached from places that do not render it, so the real limit
    // is enforced here too.
    final stock = readStock(product["stock"]);

    if (stock != null && stock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("${product["name"]} is out of stock."),
        ),
      );
      return;
    }

    final productId = product["id"]?.toString();

    if (productId == null || productId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Unable to add this product to cart."),
        ),
      );
      return;
    }

    try {
      await AppRepository.addToCart(
        productId,
        name: product["name"]?.toString() ?? "Unnamed Product",
        price: _parsePrice(product["price"]),
        imageUrl: product["image_url"]?.toString(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("${product["name"]} added to cart"),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Could not add to cart: $e")),
      );
    }
  }

  double _parsePrice(dynamic price) {
    if (price is num) return price.toDouble();

    return double.tryParse(price?.toString() ?? '') ?? 0;
  }

  Widget _buildProductImage(Map<String, dynamic> product, int? stock) {
    return Stack(
      children: [
        ProductThumbnail(
          rawImage: product["image_url"],

          // Infinite on purpose: this block is the card's flexible
          // slot, so it takes exactly the height the fixed-ratio cell
          // has left after the texts and price row have taken theirs.
          // The old fixed 140 is what pushed the price row off the
          // bottom of short cells.
          height: double.infinity,
        ),

        // The stock pill sits on the photo rather than in the text
        // block, so a line of copy never competes for the price row's
        // height. Overlaying costs nothing.
        if (stock != null)
          Positioned(
            left: 8,
            top: 8,
            child: StockBadge(stock: stock),
          ),
      ],
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final productId = product["id"]?.toString() ?? "";

    final name = product["name"]?.toString() ?? "Unnamed Product";
    final rawDescription = product["description"]?.toString();

    final description = (rawDescription == null ||
            rawDescription.trim().isEmpty)
        ? "No description available"
        : rawDescription;

    final stock = readStock(product["stock"]);

    // Only a known zero blocks the purchase. A null means the stock
    // column is missing from the database, and refusing to sell because
    // of that would break the whole catalog rather than one product.
    final soldOut = stock != null && stock <= 0;

    // Tapping the image or the text opens the details screen. The add
    // to cart button sits below both detectors so its own tap is never
    // swallowed by them.
    void openDetails() {
      if (productId.isEmpty) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProductDetailScreen(
            productId: productId,
          ),
        ),
      );
    }

    return Container(
      // Last line of defence: if an extreme font scale still overflows
      // the fixed cell, the excess is clipped to the rounded card
      // instead of painting across the neighbouring one.
      clipBehavior: Clip.antiAlias,

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The image takes the flexible slot: it soaks up whatever
          // height the fixed-ratio cell has to spare, which is what
          // guarantees the texts and the price row below always lay out
          // inside the card rather than past its bottom edge.
          Expanded(
            child: GestureDetector(
              onTap: openDetails,
              child: _buildProductImage(product, stock),
            ),
          ),

          GestureDetector(
            onTap: openDetails,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                  child: Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Price and cart button, pinned just above the card's bottom
          // edge. The row is fixed height, so it can never be squeezed
          // out of the cell again.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),

            child: Row(
              children: [
                // scaleDown rather than ellipsis: a long price shrinks
                // to fit instead of being cut to "PHP 99,9...".
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,

                    child: Text(
                      _formatPrice(product["price"]),
                      maxLines: 1,
                      style: const TextStyle(
                        color: Color(0xFFC25E7A),
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                ElevatedButton(
                  // Disabled rather than hidden, so the row does
                  // not change shape between two products and the
                  // reason is visible without a tap.
                  onPressed: soldOut ? null : () => _addToCart(product),

                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC25E7A),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        const Color(0xFFBDBDBD),
                    disabledForegroundColor: Colors.white,

                    minimumSize: const Size(42, 42),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Icon(
                    Icons.add_shopping_cart_rounded,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Edge to edge banner strip sitting between the header and the grid.
  ///
  /// A failure is swallowed rather than shown, because a broken banner
  /// row must never put an error in front of a customer; the product
  /// grid below is a completely separate subscription and is unaffected.
  ///
  /// It is still logged, though. Without that, the two most likely setup
  /// mistakes -- the table never created, and no rows inserted -- both
  /// look exactly like "no slides configured", which makes the problem
  /// impossible to spot from the screen. `debugPrint` is compiled out of
  /// release builds, so it costs a released app nothing.
  Widget _buildFeaturedCarousel() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _featuredSlidesStream,

      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint(
            'Featured slides failed to load: ${snapshot.error}',
          );
        }

        final slides = snapshot.data ?? const [];

        // Reserve the banner space while the first snapshot is still on
        // the way, so the product grid does not jump up when the slides
        // arrive. This check has to come before the empty check below:
        // while waiting, `data` is null, so `slides` is empty and the
        // early return would fire first, making this placeholder dead
        // code and causing exactly the jump it is meant to prevent.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: FeaturedSlidesCarousel.bannerHeightFor(context),
            color: const Color(0xFFFCEBEF),
          );
        }

        // No active slides, or the query failed. Either way there is
        // nothing to show, so the page simply continues.
        if (slides.isEmpty) return const SizedBox.shrink();

        return FeaturedSlidesCarousel(slides: slides);
      },
    );
  }

  /// The category chips shown under the featured banners: All Products
  /// plus the six skincare categories.
  ///
  /// Filtering happens in memory over the already-live catalog stream,
  /// so switching chips is instant and never round-trips to Supabase.
  ///
  /// These are hand-rolled pills rather than ChoiceChip on purpose: the
  /// Material chip theme pads 8 on the start and 4 on the end (space
  /// reserved for a checkmark), which leaves the label visibly right of
  /// the pill's middle. Symmetric padding centers it on both axes.
  Widget _buildCategoryFilter() {
    const rose = Color(0xFFC25E7A);
    const border = Color(0xFFF2B3C2);

    return SizedBox(
      height: 48,

      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 7, 20, 7),

        itemCount: kProductCategories.length,

        itemBuilder: (context, index) {
          final category = kProductCategories[index];
          final selected = category == _selectedCategory;

          return Padding(
            padding: const EdgeInsets.only(right: 8),

            child: Material(
              color: selected ? rose : Colors.white,

              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(17),

                side: BorderSide(
                  color: selected ? rose : border,
                ),
              ),

              child: InkWell(
                borderRadius: BorderRadius.circular(17),

                onTap: () {
                  setState(() {
                    _selectedCategory = category;
                  });
                },

                // The whole pill is the tap target and the padding is
                // perfectly symmetric, so the label sits in the middle
                // no matter how long the category name is.
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),

                  child: Text(
                    category,
                    maxLines: 1,

                    style: TextStyle(
                      color: selected ? Colors.white : rose,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// The whole storefront as one scroll surface.
  ///
  /// Nothing is locked in a fixed slice anymore: the header floats
  /// away while scrolling down and returns on the way back up, the
  /// featured banners scroll along with the content, and the category
  /// chips pin under the top of the viewport as soon as they reach it
  /// and stay there for as long as the customer is deeper in the page.
  /// Scrolling back to the top restores the natural order -- header,
  /// banners, chips, catalog.
  Widget _buildProductsPage() {
    return CustomScrollView(
      controller: _scrollController,

      slivers: [
        // Hides itself while scrolling down and slides back over the
        // content on any scroll up: the widget shows its child when the
        // user scrolls forward, toward the top, and hides it on the
        // way back down.
        SliverFloatingHeader(
          child: GradientHeader(
            toolbarTitle: "TouchSkin",
            headerTitle: "Shop products",
            subtitle:
                "Browse skincare essentials and add them to your cart.",

            actions: [
              // Only offered to a signed out customer. Once they are in,
              // the Profile tab covers signing out, so a second button
              // here would just be noise.
              if (!_isLoggedIn)
                IconButton(
                  icon: const Icon(Icons.login_rounded),
                  tooltip: "Log In",
                  onPressed: _openLogin,
                ),

              IconButton(
                icon: const Icon(Icons.shopping_cart_rounded),
                tooltip: "View Cart",
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CartScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),

        // Featured banners, edge to edge with no side padding so the
        // wide picture really does run from the left edge of the screen
        // to the right edge -- and scrolling away with the page.
        SliverToBoxAdapter(child: _buildFeaturedCarousel()),

        // Category filter row: once scrolled past it pins to the top
        // and stays reachable anywhere down the catalog; back at the
        // top it sits naturally under the banners again.
        // "All Products" is selected by default.
        SliverPersistentHeader(
          pinned: true,
          delegate: _PinnedChipsHeader(
            topInset: MediaQuery.of(context).padding.top,
            child: _buildCategoryFilter(),
          ),
        ),

        // Section title + live badge, scrolling with everything else.
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Row(
              children: [
                const Text(
                  "Available Products",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const Spacer(),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFCEBEF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.sync_rounded,
                        size: 15,
                        color: Color(0xFFC25E7A),
                      ),

                      SizedBox(width: 4),

                      Text(
                        "Live",
                        style: TextStyle(
                          color: Color(0xFFC25E7A),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // The catalog itself. The StreamBuilder sits directly in the
        // sliver list and every state below returns a sliver, so
        // loading, error, empty and the grid all live inside this one
        // scroll surface.
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _productsStream,

          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SliverFillRemaining(
                hasScrollBody: false,

                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,

                    children: [
                      CircularProgressIndicator(
                        color: Color(0xFFC25E7A),
                        strokeWidth: 2.5,
                        backgroundColor: Color(0xFFFCEBEF),
                      ),

                      SizedBox(height: 14),

                      Text(
                        "Loading products…",
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final products = snapshot.data ?? const [];

            if (snapshot.hasError) {
              return SliverFillRemaining(
                hasScrollBody: false,

                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      "Could not load products.\n${snapshot.error}",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              );
            }

            if (products.isEmpty) {
              return const SliverFillRemaining(
                hasScrollBody: false,

                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,

                    children: [
                      Icon(
                        Icons.spa_rounded,
                        size: 70,
                        color: Colors.grey,
                      ),

                      SizedBox(height: 14),

                      Text(
                        "No products available.",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      SizedBox(height: 6),

                      Text(
                        "Products will appear here once added by admin.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              );
            }

            // The chosen category narrows the catalog in memory.
            // Products the admin has not categorised yet (null
            // category) show under "All Products" and no other chip.
            final visibleProducts = _selectedCategory ==
                    kAllProductsCategory
                ? products
                : products
                    .where(
                      (product) =>
                          product['category'] == _selectedCategory,
                    )
                    .toList();

            if (visibleProducts.isEmpty) {
              return const SliverFillRemaining(
                hasScrollBody: false,

                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      "No products in this category yet.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              );
            }

            // The footer overlays the bottom of the page (Scaffold
            // extendBody), so the last row needs enough trailing
            // space to scroll clear of it: the NavigationBar's 68px
            // plus the home-indicator inset its SafeArea reserves,
            // on top of the original 20px of breathing room.
            return SliverPadding(
              padding: EdgeInsets.fromLTRB(
                16,
                6,
                16,
                20 + 68 + MediaQuery.of(context).padding.bottom,
              ),

              sliver: SliverGrid(
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 0.62,
                ),

                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    return _buildProductCard(visibleProducts[index]);
                  },
                  childCount: visibleProducts.length,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF6F2),

      // Lets the pages scroll behind the footer. Without it the
      // bottomNavigationBar slot always kept its own empty strip --
      // same colour as the page, so the grid looked cut off by an
      // invisible block after the footer slid away.
      extendBody: true,

      body: IndexedStack(
        index: _currentTabIndex,

        children: [
          _buildProductsPage(),
          const UserProfileScreen(),
        ],
      ),

      // Slides out below the screen while the page scrolls down and
      // returns on the way back up, mirroring the floating header
      // above. The slot stays reserved, so nothing jumps when the
      // footer moves.
      bottomNavigationBar: AnimatedSlide(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        offset: _footerHidden ? const Offset(0, 1) : Offset.zero,

        child: AppFooter(
          currentIndex: _currentTabIndex,

          onTap: (index) {
            setState(() {
              _currentTabIndex = index;
            });
          },
        ),
      ),
    );
  }
}
