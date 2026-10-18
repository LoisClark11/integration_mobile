import 'dart:async';

import 'package:flutter/material.dart';
import 'checkout_screen.dart';
import 'package:intl/intl.dart';
import 'session.dart';
import 'app_repository.dart';
import 'login_screen.dart';
import 'gradient_header.dart';
import 'product_image.dart';
import 'stock_label.dart';

final currencyFormatter = NumberFormat('#,##0.00');

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  /// Created once in initState. Building a stream inside `build` would
  /// re-open the realtime subscription on every rebuild, which made
  /// the page hang on the loading spinner.
  late final Stream<List<Map<String, dynamic>>> _cartStream;

  /// The cart rows carry a snapshot of the name and price but not the
  /// stock, so the catalog is streamed alongside purely to read it.
  /// Declared once for the same reason as _cartStream.
  late final Stream<List<Map<String, dynamic>>> _productsStream;

  /// The listener handle, so the catalog subscription is dropped with
  /// the screen rather than outliving it.
  StreamSubscription<List<Map<String, dynamic>>>? _productsStreamSubscription;

  /// product_id -> units on hand.
  Map<String, int?> _stockById = const {};

  @override
  void initState() {
    super.initState();

    _cartStream = AppRepository.watchCart();

    _productsStream = AppRepository.watchProducts();

    _productsStreamSubscription = _productsStream.listen((products) {
      _stockById = {
        for (final product in products)
          if (product["id"] != null)
            product["id"].toString(): readStock(product["stock"]),
      };

      // Stock moves on its own -- another customer buying shows up here
      // -- so the stepper has to be repainted when it changes.
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _productsStreamSubscription?.cancel();
    super.dispose();
  }

  /// Units left for this line, or null when the column is missing or
  /// the product has since been deleted.
  int? _stockFor(Map<String, dynamic> item) {
    final productId = item["product_id"]?.toString();

    if (productId == null || productId.isEmpty) return null;

    return _stockById[productId];
  }

  double _getPrice(Map<String, dynamic> item) {
    final price = item["price"];

    if (price is num) return price.toDouble();

    return double.tryParse(price?.toString() ?? '') ?? 0;
  }

  int _getQuantity(Map<String, dynamic> item) {
    final quantity =
        int.tryParse(item["quantity"]?.toString() ?? '1') ?? 1;

    return quantity < 1 ? 1 : quantity;
  }

  Future<void> _increaseQuantity(Map<String, dynamic> item) {
    return AppRepository.setCartQuantity(
      item["id"].toString(),
      _getQuantity(item) + 1,
    );
  }

  Future<void> _decreaseQuantity(Map<String, dynamic> item) {
    return AppRepository.setCartQuantity(
      item["id"].toString(),
      _getQuantity(item) - 1,
    );
  }

  Future<void> _deleteItem(Map<String, dynamic> item) {
    return AppRepository.removeCartItem(item["id"].toString());
  }

  Widget _buildAccessDenied(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF6F2),
      appBar: AppBar(
        title: const Text("Access Denied"),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFC25E7A),
                Color(0xFFF0A6B8),
              ],
            ),
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: const BoxDecoration(
                  color: Color(0xFFFCEBEF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  size: 48,
                  color: Color(0xFFC25E7A),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "Access Denied",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Please log in before accessing your cart.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LoginScreen(),
                    ),
                    (route) => false,
                  );
                },
                icon: const Icon(Icons.login_rounded),
                label: const Text("Go to Login"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC25E7A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWithHeader(Widget child) {
    return Column(
      children: [
        GradientHeader(
          toolbarTitle: "Shopping Cart",
          headerTitle: "Your Cart",
          subtitle: "Adjust quantities before checkout.",
          icon: Icons.shopping_cart_rounded,
          showBackButton: true,
        ),

        Expanded(child: child),
      ],
    );
  }

  Widget _buildEmptyCart() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shopping_cart_outlined,
            size: 70,
            color: Colors.grey,
          ),
          SizedBox(height: 14),
          Text(
            "Your cart is empty.",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 6),
          Text(
            "Add some products to get started.",
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItem(Map<String, dynamic> item) {
    final name = item["name"]?.toString() ?? "Unnamed Product";
    final price = _getPrice(item);
    final quantity = _getQuantity(item);
    final stock = _stockFor(item);

    // A null stock means "unknown", not "unlimited", so the stepper
    // stays open. Refusing to add would break carts on a database that
    // has not run the stock migration.
    final atStockLimit = stock != null && quantity >= stock;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 62,
                    height: 62,
                    child: ProductImage(
                      rawImage: item["image_url"],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        "PHP ${currencyFormatter.format(price)} each",
                        style: const TextStyle(
                          color: Color(0xFFC25E7A),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Subtotal: PHP ${currencyFormatter.format(price * quantity)}",
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),

                      // Warns when another customer has taken stock this
                      // cart was already counting on.
                      if (stock != null && quantity > stock) ...[
                        const SizedBox(height: 5),

                        Text(
                          "Only $stock left - reduce this to check out",
                          style: const TextStyle(
                            color: Color(0xFFD32F2F),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ] else if (stock != null) ...[
                        const SizedBox(height: 5),

                        StockLabel(stock: stock),
                      ],
                    ],
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFCEBEF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.remove_rounded,
                          color: quantity <= 1
                              ? Colors.grey
                              : const Color(0xFFC25E7A),
                        ),
                        onPressed: quantity <= 1
                            ? null
                            : () {
                                _decreaseQuantity(item);
                              },
                      ),
                      Text(
                        quantity.toString(),
                        style: const TextStyle(
                          color: Color(0xFFC25E7A),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.add_rounded,
                          color: atStockLimit
                              ? Colors.grey
                              : const Color(0xFFC25E7A),
                        ),
                        // Stops here rather than letting the customer
                        // order more than exists. The database refuses
                        // it anyway; refusing in the UI just means they
                        // find out before checkout, not during.
                        onPressed: atStockLimit
                            ? null
                            : () {
                                _increaseQuantity(item);
                              },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text("Remove"),
                onPressed: () {
                  _deleteItem(item);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomCheckout(
    BuildContext context,
    double total,
    int itemCount,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Total ($itemCount items)",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "PHP ${currencyFormatter.format(total)}",
                style: const TextStyle(
                  color: Color(0xFFC25E7A),
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CheckoutScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text(
                "Proceed to Checkout",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC25E7A),
                foregroundColor: Colors.white,
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!AppSession.isLoggedIn) {
      return _buildAccessDenied(context);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFBF6F2),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _cartStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildWithHeader(
              const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFC25E7A),
                ),
              ),
            );
          }

          if (snapshot.hasError) {
            return _buildWithHeader(
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    "Could not load your cart.\n${snapshot.error}",
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            );
          }

          final rows = snapshot.data ?? const [];

          if (rows.isEmpty) {
            return _buildWithHeader(_buildEmptyCart());
          }

          double total = 0;
          int itemCount = 0;

          final cartItems = rows.map((item) {
            final quantity = _getQuantity(item);
            final price = _getPrice(item);

            total += price * quantity;
            itemCount += quantity;

            return _buildCartItem(item);
          }).toList();

          return _buildWithHeader(
            Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                    children: cartItems,
                  ),
                ),
                _buildBottomCheckout(context, total, itemCount),
              ],
            ),
          );
        },
      ),
    );
  }
}
