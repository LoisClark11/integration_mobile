import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'gradient_header.dart';
import 'product_image.dart';
import 'checkout_screen.dart';
import 'app_repository.dart';
import 'session.dart';
import 'stock_label.dart';

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({
    super.key,
    required this.productId,
  });

  /// Primary key of the product row.
  final String productId;

  @override
  State<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  /// Shown when the product has no description in the database.
  static const String _noDescription =
      "No description available";

  final NumberFormat _currencyFormatter =
      NumberFormat('#,##0.00');

  bool _addingToCart = false;

  /// Both streams are created once in initState. Building them inside
  /// `build` would re-open the realtime subscription on every rebuild.
  late final Stream<List<Map<String, dynamic>>> _productsStream;
  late final Stream<Map<String, dynamic>?> _productStream;

  @override
  void initState() {
    super.initState();

    _productsStream = AppRepository.watchProducts();
    _productStream =
        AppRepository.watchProduct(widget.productId);
  }

  double _parsePrice(dynamic price) {
    if (price is num) return price.toDouble();

    return double.tryParse(price?.toString() ?? '') ?? 0;
  }

  String _formatPrice(dynamic price) {
    return 'PHP ${_currencyFormatter.format(_parsePrice(price))}';
  }

  /// Reads the description and falls back to a placeholder when the
  /// field is missing, empty, or null.
  String _readDescription(dynamic rawDescription) {
    if (rawDescription is! String) {
      return _noDescription;
    }

    final trimmed = rawDescription.trim();

    if (trimmed.isEmpty) {
      return _noDescription;
    }

    return trimmed;
  }

  Future<void> _addToCart(Map<String, dynamic> product) async {
    if (!AppSession.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Please log in before adding items to your cart.",
          ),
        ),
      );
      return;
    }

    if (readStock(product["stock"]) != null &&
        readStock(product["stock"])! <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "${product["name"]} is out of stock.",
          ),
        ),
      );
      return;
    }

    setState(() {
      _addingToCart = true;
    });

    try {
      await AppRepository.addToCart(
        widget.productId,
        name: product["name"]?.toString() ?? "Unnamed Product",
        price: _parsePrice(product["price"]),
        imageUrl: product["image_url"]?.toString(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "${product["name"]} added to cart",
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Could not add to cart: $e"),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _addingToCart = false;
        });
      }
    }
  }

  void _goToCheckout() {
    final product = _latestProduct;

    if (product == null) return;

    final price = _parsePrice(product["price"]);

    // Buys only this product. The saved cart is left untouched.
    final directItems = <Map<String, dynamic>>[
      {
        "productId": widget.productId,
        "name": product["name"],
        "price": price,
        "quantity": 1,
        "subtotal": price,
      },
    ];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CheckoutScreen(
          directItems: directItems,
        ),
      ),
    );
  }

  Widget _buildMainImage(dynamic rawImage) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),

      child: Container(
        height: 260,
        width: double.infinity,
        color: const Color(0xFFFCEBEF),

        child: ProductImage(
          rawImage: rawImage,
        ),
      ),
    );
  }

  Widget _buildInfoCard(Map<String, dynamic> product) {
    final name = product["name"]?.toString() ?? "Unnamed Product";
    final price = product["price"];
    final description = _readDescription(product["description"]);

    final stock = readStock(product["stock"]);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            _formatPrice(price),
            style: const TextStyle(
              color: Color(0xFFC25E7A),
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),

          if (stock != null) ...[
            const SizedBox(height: 10),

            StockLabel(
              stock: stock,
              showIcon: true,
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],

          const Divider(height: 28),

          const Text(
            "Description",
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            description,
            style: TextStyle(
              color: description == _noDescription
                  ? Colors.grey
                  : const Color(0xFF222222),
              fontSize: 14,
              height: 1.4,
              fontStyle:
                  description == _noDescription
                      ? FontStyle.italic
                      : FontStyle.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    final stock = readStock(_latestProduct?["stock"]);

    final soldOut = stock != null && stock <= 0;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,

          child: ElevatedButton.icon(
            onPressed: (_addingToCart || soldOut)
                ? null
                : () {
                    // Reuses the live value already rendered on screen.
                    _addToCart(_latestProduct ?? const {});
                  },

            icon: _addingToCart
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(
                    Icons.add_shopping_cart_rounded,
                  ),

            label: Text(
              soldOut
                  ? "Out of Stock"
                  : _addingToCart
                      ? "Adding..."
                      : "Add to Cart",
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),

            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC25E7A),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFFCEBEF),
              elevation: 2,

              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        SizedBox(
          width: double.infinity,
          height: 52,

          child: OutlinedButton.icon(
            onPressed: _goToCheckout,

            icon: const Icon(
              Icons.local_shipping_rounded,
            ),

            label: const Text(
              "Checkout Now",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),

            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFC25E7A),
              side: const BorderSide(
                color: Color(0xFFC25E7A),
              ),

              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Last product payload seen by the stream, so the add to cart
  /// button can reuse it without another network read.
  Map<String, dynamic>? _latestProduct;

  Widget _buildRelatedCard(
    String productId,
    Map<String, dynamic> product,
  ) {
    final name = product["name"]?.toString() ?? "Unnamed Product";

    return SizedBox(
      width: 130,

      child: GestureDetector(
        onTap: () {
          // Replaces this page so back returns to the product grid
          // instead of walking through every visited product.
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => ProductDetailScreen(
                productId: productId,
              ),
            ),
          );
        },

        child: Container(
          padding: const EdgeInsets.all(8),

          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),

            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),

                child: Container(
                  height: 90,
                  width: double.infinity,
                  color: const Color(0xFFFCEBEF),

                  child: ProductImage(
                    rawImage: product["image_url"],
                  ),
                ),
              ),

              const SizedBox(height: 8),

              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 3),

              Text(
                _formatPrice(product["price"]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFC25E7A),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRelatedProducts() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _productsStream,

      builder: (context, snapshot) {
        final all = snapshot.data ?? const [];

        final related = <MapEntry<String, Map<String, dynamic>>>[];

        for (final product in all) {
          final productId = product["id"]?.toString() ?? "";

          // The current product is not listed as related to itself.
          if (productId.isEmpty || productId == widget.productId) {
            continue;
          }

          related.add(MapEntry(productId, product));
        }

        if (related.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),

            const Text(
              "Other Products",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              height: 185,

              child: ListView.separated(
                scrollDirection: Axis.horizontal,

                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                ),

                itemCount: related.length,

                separatorBuilder: (context, index) {
                  return const SizedBox(width: 12);
                },

                itemBuilder: (context, index) {
                  final entry = related[index];

                  return _buildRelatedCard(
                    entry.key,
                    entry.value,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF6F2),

      body: StreamBuilder<Map<String, dynamic>?>(
        stream: _productStream,

        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFC25E7A),
              ),
            );
          }

          final product = snapshot.data;

          if (product == null) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 70,
                    color: Colors.grey,
                  ),

                  SizedBox(height: 14),

                  Text(
                    "Product no longer available.",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          }

          _latestProduct = product;

          return Column(
            children: [
              GradientHeader(
                toolbarTitle: "Product Details",
                headerTitle: product["name"]?.toString() ??
                    "Unnamed Product",
                subtitle: "Review this item before buying.",
                icon: Icons.inventory_2_rounded,
                showBackButton: true,
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),

                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      _buildMainImage(
                        product["image_url"],
                      ),

                      const SizedBox(height: 16),

                      _buildInfoCard(product),

                      const SizedBox(height: 16),

                      _buildActionButtons(),

                      _buildRelatedProducts(),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}