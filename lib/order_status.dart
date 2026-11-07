import 'package:flutter/material.dart';

/// The four values `public.orders.status` may hold.
///
/// Pending is the default at checkout. An admin moves the order through
/// Processing and Delivered. Either side may cancel while it is still
/// Pending or Processing; Delivered and Cancelled are final.
enum OrderStatus {
  pending,
  processing,
  delivered,
  cancelled,
}

/// Parses the database value.
///
/// A null, blank or unknown value falls back to Pending: a row that has
/// just been written by `place_order` is Pending, so treating an unreadable
/// status as Pending is safer than claiming the order was delivered.
OrderStatus readOrderStatus(dynamic raw) {
  switch (raw?.toString().trim().toLowerCase()) {
    case 'processing':
      return OrderStatus.processing;
    case 'delivered':
      return OrderStatus.delivered;
    case 'cancelled':
    case 'canceled':
      return OrderStatus.cancelled;
    case 'pending':
    default:
      return OrderStatus.pending;
  }
}

extension OrderStatusDisplay on OrderStatus {
  String get label {
    switch (this) {
      case OrderStatus.pending:
        return 'Pending';
      case OrderStatus.processing:
        return 'Processing';
      case OrderStatus.delivered:
        return 'Delivered';
      case OrderStatus.cancelled:
        return 'Cancelled';
    }
  }

  String get description {
    switch (this) {
      case OrderStatus.pending:
        return 'We received your order. It is waiting to be processed.';
      case OrderStatus.processing:
        return 'We are preparing your order for delivery.';
      case OrderStatus.delivered:
        return 'This order has been delivered. Thank you!';
      case OrderStatus.cancelled:
        return 'This order was cancelled.';
    }
  }

  IconData get icon {
    switch (this) {
      case OrderStatus.pending:
        return Icons.schedule_rounded;
      case OrderStatus.processing:
        return Icons.local_shipping_rounded;
      case OrderStatus.delivered:
        return Icons.check_circle_rounded;
      case OrderStatus.cancelled:
        return Icons.cancel_rounded;
    }
  }

  Color get color {
    switch (this) {
      case OrderStatus.pending:
        return const Color(0xFFB45309);
      case OrderStatus.processing:
        return const Color(0xFF1D4ED8);
      case OrderStatus.delivered:
        return const Color(0xFF2E7D32);
      case OrderStatus.cancelled:
        return Colors.redAccent;
    }
  }

  Color get background {
    switch (this) {
      case OrderStatus.pending:
        return const Color(0xFFFFF7E6);
      case OrderStatus.processing:
        return const Color(0xFFE8F0FE);
      case OrderStatus.delivered:
        return const Color(0xFFE8F5E9);
      case OrderStatus.cancelled:
        return const Color(0xFFFDECEA);
    }
  }

  /// The customer app may only cancel while the order is still with the
  /// shop. Delivered and Cancelled are final.
  bool get canCustomerCancel =>
      this == OrderStatus.pending || this == OrderStatus.processing;

  bool get isCancelled => this == OrderStatus.cancelled;
}
