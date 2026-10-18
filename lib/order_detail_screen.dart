import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'gradient_header.dart';
import 'app_repository.dart';

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({
    super.key,
    required this.orderId,
  });

  /// Primary key of the order row.
  final String orderId;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final NumberFormat _currencyFormatter =
      NumberFormat('#,##0.00');

  bool _cancelling = false;

  /// Created once in initState so the realtime subscription is not
  /// re-opened on every rebuild.
  late final Stream<Map<String, dynamic>?> _orderStream;

  @override
  void initState() {
    super.initState();

    _orderStream = AppRepository.watchOrder(widget.orderId);
  }

  double _parseAmount(dynamic amount) {
    if (amount is num) return amount.toDouble();

    return double.tryParse(amount?.toString() ?? '') ?? 0;
  }

  String _formatCurrency(dynamic amount) {
    return 'PHP ${_currencyFormatter.format(_parseAmount(amount))}';
  }

  String _readDate(dynamic createdAt) {
    if (createdAt is! String || createdAt.isEmpty) {
      return "Date unavailable";
    }

    final parsed = DateTime.tryParse(createdAt);

    if (parsed == null) return "Date unavailable";

    return DateFormat("MMM d, yyyy - h:mm a").format(parsed.toLocal());
  }

  bool _isCancelled(Map<String, dynamic> order) {
    return order["status"]?.toString().toLowerCase() == "cancelled";
  }

  Future<void> _cancelOrder() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),

          title: const Text("Cancel this order?"),

          content: const Text(
            "This marks the order as cancelled. "
            "This action cannot be undone.",
          ),

          actionsAlignment: MainAxisAlignment.center,

          actions: [
            SizedBox(
              width: 110,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(context, false);
                },

                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey,
                  side: const BorderSide(color: Colors.grey),

                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),

                child: const Text("Keep"),
              ),
            ),

            SizedBox(
              width: 110,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context, true);
                },

                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,

                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),

                child: const Text("Cancel"),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() {
      _cancelling = true;
    });

    try {
      await AppRepository.cancelOrder(widget.orderId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Order cancelled."),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Could not cancel order: $e"),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _cancelling = false;
        });
      }
    }
  }

  Widget _buildDetailRow(
    String label,
    String value, {
    bool isBold = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey,
              fontWeight: isBold
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),

          const SizedBox(width: 16),

          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: isBold ? 17 : null,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsList(dynamic rawItems) {
    if (rawItems is! List || rawItems.isEmpty) {
      return const Text(
        "No items recorded for this order.",
        style: TextStyle(color: Colors.grey),
      );
    }

    return Column(
      children: rawItems.map((rawItem) {
        final item = rawItem as Map<String, dynamic>;

        final name = item["name"]?.toString() ?? "Product";
        final quantity =
            int.tryParse(item["quantity"]?.toString() ?? '1') ?? 1;
        final price = item["price"];
        final subtotal = item["subtotal"];

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),

          decoration: BoxDecoration(
            color: const Color(0xFFF7F9FC),
            borderRadius: BorderRadius.circular(16),
          ),

          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,

                decoration: BoxDecoration(
                  color: const Color(0xFFFCEBEF),
                  borderRadius: BorderRadius.circular(12),
                ),

                child: const Icon(
                  Icons.inventory_2_rounded,
                  size: 22,
                  color: Color(0xFFC25E7A),
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 3),

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

              Text(
                _formatCurrency(subtotal),
                style: const TextStyle(
                  color: Color(0xFFC25E7A),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Future<void> _deleteOrder() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),

          title: const Text("Delete this order?"),

          content: const Text(
            "This permanently removes the order from "
            "your history. This action cannot be undone.",
          ),

          actionsAlignment: MainAxisAlignment.center,

          actions: [
            SizedBox(
              width: 110,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(context, false);
                },

                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey,
                  side: const BorderSide(color: Colors.grey),

                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),

                child: const Text("Keep"),
              ),
            ),

            SizedBox(
              width: 110,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context, true);
                },

                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,

                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),

                child: const Text("Delete"),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() {
      _cancelling = true;
    });

    try {
      await AppRepository.deleteOrder(widget.orderId);

      if (!mounted) return;

      // Return to the order list, where the stream no longer
      // contains this order.
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Order deleted."),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Could not delete order: $e"),
        ),
      );

      setState(() {
        _cancelling = false;
      });
    }
  }

  Widget _buildActionButton(bool isCancelled) {
    // A cancelled order can be deleted outright. An active order
    // can only be cancelled.
    final bool isDeleteMode = isCancelled;

    return SizedBox(
      width: double.infinity,
      height: 52,

      child: OutlinedButton.icon(
        onPressed: _cancelling
            ? null
            : () {
                if (isDeleteMode) {
                  _deleteOrder();
                } else {
                  _cancelOrder();
                }
              },

        icon: _cancelling
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.redAccent,
                ),
              )
            : Icon(
                isDeleteMode
                    ? Icons.delete_outline_rounded
                    : Icons.cancel_outlined,
              ),

        label: Text(
          _cancelling
              ? (isDeleteMode
                    ? "Deleting..."
                    : "Cancelling...")
              : (isDeleteMode
                    ? "Delete Order"
                    : "Cancel Order"),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),

        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.redAccent,
          disabledForegroundColor: Colors.grey,
          side: const BorderSide(color: Colors.redAccent),

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF6F2),

      body: StreamBuilder<Map<String, dynamic>?>(
        stream: _orderStream,

        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFC25E7A),
              ),
            );
          }

          final order = snapshot.data;

          if (order == null) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 70,
                    color: Colors.grey,
                  ),

                  SizedBox(height: 14),

                  Text(
                    "Order no longer available.",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          }

          final isCancelled = _isCancelled(order);

          final status = isCancelled
              ? "Cancelled"
              : (order["status"]?.toString() ?? "Completed");

          return Column(
            children: [
              GradientHeader(
                toolbarTitle: "Order Details",
                headerTitle: "Order Summary",
                subtitle: "Review or cancel this order.",
                icon: Icons.receipt_long_rounded,
                showBackButton: true,
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),

                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      // Status
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),

                        decoration: BoxDecoration(
                          color: isCancelled
                              ? const Color(0xFFFDECEA)
                              : const Color(0xFFE8F5E9),
                          borderRadius:
                              BorderRadius.circular(18),
                        ),

                        child: Row(
                          children: [
                            Icon(
                              isCancelled
                                  ? Icons.cancel_rounded
                                  : Icons.check_circle_rounded,
                              color: isCancelled
                                  ? Colors.redAccent
                                  : const Color(0xFF2E7D32),
                            ),

                            const SizedBox(width: 10),

                            Text(
                              status,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: isCancelled
                                    ? Colors.redAccent
                                    : const Color(0xFF2E7D32),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Order info
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),

                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius:
                              BorderRadius.circular(22),

                          boxShadow: [
                            BoxShadow(
                              color: Colors.black
                                  .withValues(alpha: 0.05),
                              blurRadius: 15,
                              offset:
                                  const Offset(0, 6),
                            ),
                          ],
                        ),

                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Order Information",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),

                            const SizedBox(height: 14),

                            _buildDetailRow(
                              "Date",
                              _readDate(
                                order["created_at"],
                              ),
                            ),

                            _buildDetailRow(
                              "Customer",
                              order["customer_name"]
                                      ?.toString() ??
                                  "N/A",
                            ),

                            _buildDetailRow(
                              "Address",
                              order["address"]
                                      ?.toString() ??
                                  "N/A",
                            ),

                            _buildDetailRow(
                              "Payment",
                              order["payment_method"]
                                      ?.toString() ??
                                  "N/A",
                            ),

                            _buildDetailRow(
                              "Order ID",
                              widget.orderId,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Items
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),

                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius:
                              BorderRadius.circular(22),

                          boxShadow: [
                            BoxShadow(
                              color: Colors.black
                                  .withValues(alpha: 0.05),
                              blurRadius: 15,
                              offset:
                                  const Offset(0, 6),
                            ),
                          ],
                        ),

                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Items (${order["item_count"] ?? 0})",
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),

                            const SizedBox(height: 14),

                            _buildItemsList(
                              order["items"],
                            ),

                            const Divider(height: 24),

                            _buildDetailRow(
                              "Subtotal",
                              _formatCurrency(
                                order["subtotal_amount"],
                              ),
                            ),

                            _buildDetailRow(
                              "Delivery Fee",
                              _formatCurrency(
                                order["delivery_fee"],
                              ),
                            ),

                            const Divider(height: 18),

                            _buildDetailRow(
                              "Total",
                              _formatCurrency(
                                order["total_amount"],
                              ),
                              isBold: true,
                              valueColor:
                                  const Color(0xFFC25E7A),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Cancel button
                      _buildActionButton(isCancelled),

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