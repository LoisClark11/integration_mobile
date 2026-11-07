import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';
import 'session.dart';

/// All database access lives here so the screens stay declarative and
/// the table and column names are defined in one place.
class AppRepository {
  AppRepository._();

  static SupabaseClient get _client => SupabaseService.client;

  // ======================================================================
  // Products
  // ======================================================================

  /// Live list of products for the storefront grid.
  ///
  /// Call this once per screen from `State.initState` and keep the
  /// result in a field. Never build a stream inside `build`, because
  /// every call opens a brand new realtime subscription.
  static Stream<List<Map<String, dynamic>>> watchProducts() {
    return _client
        .from('products')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .map((rows) => rows);
  }

  /// Single product, used by the details screen.
  static Stream<Map<String, dynamic>?> watchProduct(String productId) {
    return _client
        .from('products')
        .stream(primaryKey: ['id'])
        .eq('id', productId)
        .map(
          (rows) => rows.isEmpty ? null : rows.first,
        );
  }

  // ======================================================================
  // Featured slides
  // ======================================================================

  /// Live list of active featured slides in carousel order.
  ///
  /// The `is_active` filter is applied by PostgREST, so drafts never
  /// reach the device at all.
  ///
  /// `ascending: true` is not optional here. The stream builder sorts
  /// newest first unless told otherwise, so leaving it off would show
  /// the carousel running backwards.
  static Stream<List<Map<String, dynamic>>> watchFeaturedSlides() {
    return _client
        .from('featured_slides')
        .stream(primaryKey: ['id'])
        .eq('is_active', true)
        .order('display_order', ascending: true)
        .map((rows) => rows);
  }

  // ======================================================================
  // Cart
  // ======================================================================

  /// Adds one to the quantity for a product, or creates the line when
  /// the product is not in the cart yet.
  static Future<void> addToCart(
    String productId, {
    required String name,
    required num price,
    String? imageUrl,
  }) async {
    final userId = AppSession.userId;

    if (userId == null) return;

    final existing = await _client
        .from('cart_items')
        .select('id, quantity')
        .eq('user_id', userId)
        .eq('product_id', productId)
        .maybeSingle();

    final nextQuantity = ((existing?['quantity'] as int?) ?? 0) + 1;

    // Upsert on the (user_id, product_id) unique key rather than a plain
    // insert. Two quick taps used to both read "no row yet" and both
    // insert, and the loser surfaced a raw 23505 unique-violation to the
    // customer. Writing through the key instead means a concurrent
    // insert just becomes the conflict target, so the call always
    // succeeds and the row is simply updated.
    await _client.from('cart_items').upsert(
      {
        'user_id': userId,
        'product_id': productId,
        'quantity': nextQuantity,
        'name': name,
        'price': price,
        'image_url': imageUrl,
      },
      onConflict: 'user_id,product_id',
    );
  }

  /// Live cart lines for the signed in user.
  static Stream<List<Map<String, dynamic>>> watchCart() {
    final userId = AppSession.userId;

    if (userId == null) {
      return const Stream<List<Map<String, dynamic>>>.empty();
    }

    return _client
        .from('cart_items')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .map((rows) => rows);
  }

  /// Cart line ids are `uuid` columns, so Postgres hands them back as
  /// strings rather than numbers.
  static Future<void> setCartQuantity(
    String cartItemId,
    int quantity,
  ) async {
    final userId = AppSession.userId;

    if (userId == null) return;

    if (quantity <= 0) {
      await removeCartItem(cartItemId);
      return;
    }

    await _client
        .from('cart_items')
        .update({'quantity': quantity})
        .eq('id', cartItemId)
        .eq('user_id', userId);
  }

  static Future<void> removeCartItem(String cartItemId) async {
    final userId = AppSession.userId;

    if (userId == null) return;

    await _client
        .from('cart_items')
        .delete()
        .eq('id', cartItemId)
        .eq('user_id', userId);
  }

  static Future<void> clearCart() async {
    final userId = AppSession.userId;

    if (userId == null) return;

    await _client
        .from('cart_items')
        .delete()
        .eq('user_id', userId);
  }

  // ======================================================================
  // Orders
  // ======================================================================

  /// Places an order and takes the matching stock off every product.
  ///
  /// This calls the `place_order` function rather than inserting into
  /// `orders` directly. That is deliberate: the stock check and the
  /// stock decrement happen in one statement inside Postgres, so two
  /// customers buying the last unit cannot both win. Doing the same
  /// arithmetic here would be a read followed by a write, with a window
  /// in between where both of them see the same number.
  ///
  /// Throws a [PostgrestException] when an item is short. The message is
  /// written to be shown to a customer, so the checkout screen can pass
  /// it straight through.
  static Future<void> createOrder({
    required String customerName,
    required String address,
    required String paymentMethod,
    required double subtotal,
    required double deliveryFee,
    required double total,
    required int itemCount,
    required List<Map<String, dynamic>> items,
    required String purchaseType,
  }) async {
    final userId = AppSession.userId;

    if (userId == null) return;

    await _client.rpc('place_order', params: {
      'p_customer_name': customerName,
      'p_address': address,
      'p_payment_method': paymentMethod,
      'p_subtotal': subtotal,
      'p_delivery_fee': deliveryFee,
      'p_total': total,
      'p_item_count': itemCount,
      'p_items': items,
      'p_purchase_type': purchaseType,
    });
  }

  /// Live order history for the signed in user, newest first.
  static Stream<List<Map<String, dynamic>>> watchOrders() {
    final userId = AppSession.userId;

    if (userId == null) {
      return const Stream<List<Map<String, dynamic>>>.empty();
    }

    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .map((rows) => rows);
  }

  static Stream<Map<String, dynamic>?> watchOrder(String orderId) {
    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('id', orderId)
        .map(
          (rows) => rows.isEmpty ? null : rows.first,
        );
  }

  static Future<void> cancelOrder(String orderId) async {
    final userId = AppSession.userId;

    if (userId == null) return;

    // `.select()` is what proves a row was actually changed. Without it
    // PostgREST reports success even when the RLS policy matched nothing,
    // and the screen would claim the order was cancelled when it was not.
    // The database guard still rejects a Delivered order with a 42501
    // PostgrestException, which the screen shows as-is.
    final rows = await _client
        .from('orders')
        .update({
          'status': 'Cancelled',
          'cancelled_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', orderId)
        .eq('user_id', userId)
        .select('id');

    if (rows.isEmpty) {
      throw Exception(
        'This order can no longer be cancelled. It may already be delivered.',
      );
    }
  }

  static Future<void> deleteOrder(String orderId) async {
    final userId = AppSession.userId;

    if (userId == null) return;

    final rows = await _client
        .from('orders')
        .delete()
        .eq('id', orderId)
        .eq('user_id', userId)
        .select('id');

    if (rows.isEmpty) {
      throw Exception('This order could not be deleted.');
    }
  }

  // ======================================================================
  // Profile
  // ======================================================================

  static Stream<Map<String, dynamic>?> watchProfile() {
    final userId = AppSession.userId;

    if (userId == null) {
      return const Stream<Map<String, dynamic>?>.empty();
    }

    return _client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', userId)
        .map(
          (rows) => rows.isEmpty ? null : rows.first,
        );
  }

  static Future<void> updateProfileImage(String publicUrl) async {
    final userId = AppSession.userId;

    if (userId == null) return;

    await _client
        .from('profiles')
        .update({'profile_image': publicUrl})
        .eq('id', userId);
  }
}