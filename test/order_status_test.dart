import 'package:flutter_test/flutter_test.dart';
import 'package:integration_mobile/order_status.dart';

/// The status column is the one field both apps write and read, so its
/// parsing and cancellation rules are worth pinning down.
void main() {
  group('readOrderStatus', () {
    test('reads every stored value', () {
      expect(readOrderStatus('Pending'), OrderStatus.pending);
      expect(readOrderStatus('Processing'), OrderStatus.processing);
      expect(readOrderStatus('Delivered'), OrderStatus.delivered);
      expect(readOrderStatus('Cancelled'), OrderStatus.cancelled);
    });

    test('is case and whitespace insensitive', () {
      expect(readOrderStatus(' processing '), OrderStatus.processing);
      expect(readOrderStatus('DELIVERED'), OrderStatus.delivered);
    });

    test('accepts the one-L spelling of cancelled', () {
      expect(readOrderStatus('canceled'), OrderStatus.cancelled);
    });

    test('falls back to pending when the value is missing or unknown', () {
      // A freshly placed order is Pending, so an unreadable value must not
      // claim the order was delivered.
      expect(readOrderStatus(null), OrderStatus.pending);
      expect(readOrderStatus(''), OrderStatus.pending);
      expect(readOrderStatus('Completed'), OrderStatus.pending);
    });
  });

  group('display', () {
    test('labels match the database values', () {
      expect(OrderStatus.pending.label, 'Pending');
      expect(OrderStatus.processing.label, 'Processing');
      expect(OrderStatus.delivered.label, 'Delivered');
      expect(OrderStatus.cancelled.label, 'Cancelled');
    });

    test('every status has a description and an icon', () {
      for (final status in OrderStatus.values) {
        expect(status.description, isNotEmpty);
        expect(status.icon, isNotNull);
      }
    });
  });

  group('canCustomerCancel', () {
    test('is true only while the order is still being handled', () {
      expect(OrderStatus.pending.canCustomerCancel, isTrue);
      expect(OrderStatus.processing.canCustomerCancel, isTrue);
      expect(OrderStatus.delivered.canCustomerCancel, isFalse);
      expect(OrderStatus.cancelled.canCustomerCancel, isFalse);
    });
  });
}
