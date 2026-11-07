import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'currency_format.dart';
import 'session.dart';
import 'app_repository.dart';
import 'supabase_service.dart';
import 'login_screen.dart';
import 'gradient_header.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({
    super.key,
    this.directItems,
  });

  /// When provided, the screen checks out these items directly
  /// instead of reading the user's saved cart.
  final List<Map<String, dynamic>>? directItems;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

/// Turns a failed `place_order` into something worth reading.
///
/// The function writes its own message, naming the product that ran
/// short, so that text is worth surfacing. A raw PostgrestException
/// stringifies to something useless on a phone, so anything
/// unrecognised falls back to a plain apology.
String _readOrderError(Object error) {
  if (error is PostgrestException) {
    final message = error.message.trim();

    if (message.isNotEmpty) {
      return message.startsWith("Not enough stock")
          ? message
          : "Could not place the order: $message";
    }
  }

  return "Could not place the order. Please try again.";
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController =
      TextEditingController();

  final TextEditingController _addressController =
      TextEditingController();

  String? _paymentMethod;

  bool _processing = false;

  static const double _deliveryFee = 50;

  /// Created once in initState so the realtime subscription survives
  /// rebuilds instead of being re-opened each time.
  late final Stream<List<Map<String, dynamic>>> _cartStream;

  @override
  void initState() {
    super.initState();

    _cartStream = AppRepository.watchCart();
  }

  double _getPrice(Map<String, dynamic> item) => CurrencyFormat.parse(item["price"]);

  int _getQuantity(Map<String, dynamic> item) =>
      CurrencyFormat.parseQuantity(item["quantity"]);

  String _formatCurrency(double amount) => CurrencyFormat.php(amount);

  /// True when this screen checks out a single product straight from
  /// its details page rather than the saved cart.
  bool get _isDirectCheckout =>
      widget.directItems != null &&
      widget.directItems!.isNotEmpty;

  /// Converts cart rows into the shared item shape used by the
  /// summary and the stored order.
  List<Map<String, dynamic>> _normalizeItems(
    List<Map<String, dynamic>> rows,
  ) {
    final List<Map<String, dynamic>> items = [];

    for (final item in rows) {
      final price = _getPrice(item);
      final quantity = _getQuantity(item);

      items.add({
        "productId": item["product_id"],
        "name": item["name"],
        "price": price,
        "quantity": quantity,
        "subtotal": price * quantity,
      });
    }

    return items;
  }

  Map<String, dynamic> _buildSummaryTotals(
    List<Map<String, dynamic>> items,
  ) {
    double subtotal = 0;
    int itemCount = 0;

    for (final item in items) {
      subtotal += (item["price"] as double) *
          (item["quantity"] as int);
      itemCount += item["quantity"] as int;
    }

    return {
      "subtotal": subtotal,
      "itemCount": itemCount,
      "total": subtotal + _deliveryFee,
    };
  }

  Widget _buildSummaryRow(
    String label, {
    required String value,
    bool isBold = false,
    bool isMuted = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold
                  ? FontWeight.bold
                  : FontWeight.normal,
              color: isMuted ? Colors.grey : null,
            ),
          ),

          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: isBold ? 18 : null,
              color: isBold
                  ? const Color(0xFFC25E7A)
                  : (isMuted ? Colors.grey : null),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderSummary() {
    // Direct checkout shows the single product being bought now.
    if (_isDirectCheckout) {
      final items = widget.directItems!;

      final totals = _buildSummaryTotals(items);

      return _buildSummaryCard(
        items: items,
        subtotal: totals["subtotal"] as double,
        itemCount: totals["itemCount"] as int,
        total: totals["total"] as double,
      );
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _cartStream,
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const [];

        final items = _normalizeItems(rows);

        if (items.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Text(
              "Your cart is empty.",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          );
        }

        final totals = _buildSummaryTotals(items);

        return _buildSummaryCard(
          items: items,
          subtotal: totals["subtotal"] as double,
          itemCount: totals["itemCount"] as int,
          total: totals["total"] as double,
        );
      },
    );
  }

  Widget _buildSummaryCard({
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required int itemCount,
    required double total,
  }) {
    final itemRows = items.map((item) {
      final price = item["price"] as double;
      final quantity = item["quantity"] as int;

      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9FC),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item["name"]?.toString() ?? "Unnamed Product",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    "${_formatCurrency(price)} x $quantity",
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            Text(
              _formatCurrency(price * quantity),
              style: const TextStyle(
                color: Color(0xFFC25E7A),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }).toList();

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
          const Text(
            "Order Summary",
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          ...itemRows,
          const Divider(height: 22),

          _buildSummaryRow(
            "Subtotal ($itemCount items)",
            value: _formatCurrency(subtotal),
          ),

          _buildSummaryRow(
            "Delivery Fee",
            value: _formatCurrency(_deliveryFee),
          ),

          const Divider(height: 18),

          _buildSummaryRow(
            "Total",
            value: _formatCurrency(total),
            isBold: true,
          ),
        ],
      ),
    );
  }

  Future<void> _processTransaction() async {
    // Validate the form first
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_paymentMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please select a payment method."),
        ),
      );
      return;
    }

    setState(() {
      _processing = true;
    });

    try {
      List<Map<String, dynamic>> items;

      if (_isDirectCheckout) {
        // Buying straight from a product page, no cart read needed.
        items = widget.directItems!;
      } else {
        // The session can end between the first build and this tap (a
        // sign-out elsewhere, or an expired token). Re-check rather than
        // force-unwrap, which would crash on a null id.
        final userId = AppSession.userId;

        if (userId == null) {
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Please sign in again to continue."),
            ),
          );

          setState(() {
            _processing = false;
          });

          return;
        }

        // Read the cart rows directly so the order reflects what was
        // on screen when the customer confirmed.
        final rows = await SupabaseService.client
            .from('cart_items')
            .select()
            .eq('user_id', userId);

        if (!mounted) return;

        items = _normalizeItems(rows);
      }

      if (items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Your cart is empty."),
          ),
        );

        setState(() {
          _processing = false;
        });

        return;
      }

      final totals = _buildSummaryTotals(items);

      final subtotal = totals["subtotal"] as double;
      final itemCount = totals["itemCount"] as int;
      final total = totals["total"] as double;

      // Save the order
      await AppRepository.createOrder(
        customerName: _nameController.text.trim(),
        address: _addressController.text.trim(),
        paymentMethod: _paymentMethod!,
        subtotal: subtotal,
        deliveryFee: _deliveryFee,
        total: total,
        itemCount: itemCount,
        items: items,
        purchaseType: _isDirectCheckout ? 'Buy Now' : 'Cart',
      );

      // Only a cart checkout empties the saved cart. A direct
      // purchase must leave the user's existing cart untouched.
      if (!_isDirectCheckout) {
        await AppRepository.clearCart();
      }

      if (!mounted) return;

      setState(() {
        _processing = false;
      });

      // Show success message
      await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFCEBEF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Color(0xFFC25E7A),
                    size: 38,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Transaction Successful",
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            content: Text(
              "Your transaction has been completed.\n\n"
              "Total: ${CurrencyFormat.php(total)}",
              textAlign: TextAlign.center,
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              SizedBox(
                width: 120,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        const Color(0xFFC25E7A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text("OK"),
                ),
              ),
            ],
          );
        },
      );

      if (!mounted) return;

      // Return to Dashboard
      Navigator.pop(context);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _processing = false;
      });

      // place_order() refuses the whole order when one line is short,
      // and its message names the product. Showing that verbatim beats
      // "Transaction failed: [object Object]", which is all a raw
      // PostgrestException stringifies to on the phone.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text(_readOrderError(e)),
        ),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppSession.isLoggedIn) {
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
            const Icon(
              Icons.lock_outline_rounded,
              size: 80,
              color: Color(0xFFC25E7A),
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
              "Please log in before accessing checkout.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey,
              ),
            ),

            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LoginScreen(),
                  ),
                  (route) => false,
                );
              },
              child: const Text("Go to Login"),
            ),
          ],
        ),
      ),
    ),
  );
}
    return Scaffold(
      backgroundColor: const Color(0xFFFBF6F2),

      body: Column(
        children: [
          GradientHeader(
            toolbarTitle: "Checkout",
            headerTitle: "Complete Your Order",
            subtitle:
                "Enter your details to complete the transaction.",
            icon: Icons.shopping_bag_rounded,
            showBackButton: true,
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),

              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,

                children: [

            _buildOrderSummary(),

            const SizedBox(height: 18),

            // ==========================
            // FORM CARD
            // ==========================

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),

              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.circular(22),

                boxShadow: [
                  BoxShadow(
                    color:
                        Colors.black.withValues(alpha: 0.05),
                    blurRadius: 15,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),

              child: Form(
                key: _formKey,

                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,

                  children: [
                    const Text(
                      "Customer Information",
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Customer Name
                    TextFormField(
                      controller: _nameController,

                      decoration: InputDecoration(
                        labelText: "Customer Name",
                        prefixIcon: const Icon(
                          Icons.person_outline_rounded,
                        ),

                        filled: true,
                        fillColor:
                            const Color(0xFFF7F9FC),

                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(14),
                          borderSide:
                              BorderSide.none,
                        ),

                        focusedBorder:
                            OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(
                            color:
                                Color(0xFFC25E7A),
                            width: 2,
                          ),
                        ),
                      ),

                      validator: (value) {
                        if (value == null ||
                            value.trim().isEmpty) {
                          return "Customer Name is required.";
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    // Address
                    TextFormField(
                      controller:
                          _addressController,

                      maxLines: 3,

                      decoration: InputDecoration(
                        labelText: "Address",
                        alignLabelWithHint: true,

                        prefixIcon: const Padding(
                          padding:
                              EdgeInsets.only(
                            bottom: 42,
                          ),
                          child: Icon(
                            Icons.location_on_outlined,
                          ),
                        ),

                        filled: true,
                        fillColor:
                            const Color(0xFFF7F9FC),

                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(14),
                          borderSide:
                              BorderSide.none,
                        ),

                        focusedBorder:
                            OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(
                            color:
                                Color(0xFFC25E7A),
                            width: 2,
                          ),
                        ),
                      ),

                      validator: (value) {
                        if (value == null ||
                            value.trim().isEmpty) {
                          return "Address is required.";
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    // Payment Method
                    DropdownButtonFormField<String>(
                      initialValue: _paymentMethod,

                      decoration: InputDecoration(
                        labelText: "Payment Method",

                        prefixIcon: const Icon(
                          Icons.payment_rounded,
                        ),

                        filled: true,
                        fillColor:
                            const Color(0xFFF7F9FC),

                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(14),
                          borderSide:
                              BorderSide.none,
                        ),

                        focusedBorder:
                            OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(
                            color:
                                Color(0xFFC25E7A),
                            width: 2,
                          ),
                        ),
                      ),

                      items: const [
                        DropdownMenuItem(
                          value: "Cash",
                          child: Text("Cash"),
                        ),
                        DropdownMenuItem(
                          value: "GCash",
                          child: Text("GCash"),
                        ),
                        DropdownMenuItem(
                          value: "Card",
                          child: Text("Card"),
                        ),
                      ],

                      onChanged: (value) {
                        setState(() {
                          _paymentMethod = value;
                        });
                      },

                      validator: (value) {
                        if (value == null) {
                          return "Please select a payment method.";
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 26),

                    // Checkout Button
                    SizedBox(
                      width: double.infinity,
                      height: 52,

                      child: ElevatedButton.icon(
                        onPressed: _processing
                            ? null
                            : _processTransaction,

                        icon: _processing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.check_circle_outline,
                              ),

                        label: Text(
                          _processing
                              ? "Processing..."
                              : "Complete Checkout",

                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),

                        style:
                            ElevatedButton.styleFrom(
                          backgroundColor:
                              const Color(0xFFC25E7A),

                          foregroundColor:
                              Colors.white,

                          disabledBackgroundColor:
                              const Color(0xFFFCEBEF),

                          elevation: 2,

                          shape:
                              RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Small footer note
            const Center(
              child: Text(
                "Please review your information before completing the order.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                ),
              ),
            ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
