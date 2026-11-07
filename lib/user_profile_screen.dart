import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'currency_format.dart';
import 'gradient_header.dart';
import 'change_password_screen.dart';
import 'create_account_screen.dart';
import 'order_detail_screen.dart';
import 'order_status.dart';
import 'cart_screen.dart';
import 'login_screen.dart';
import 'app_repository.dart';
import 'supabase_service.dart';
import 'session.dart';
import 'session_persistence.dart';
import 'touchskin_cache.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  /// Public bucket that profile pictures are uploaded to.
  static const String _avatarBucket = 'avatars';

  /// Shown until the user picks a picture, and if a saved picture
  /// fails to load. A person glyph reads more clearly as an avatar
  /// than the generic product placeholder did.
  ///
  /// The size is capped deliberately. The avatar is a 110px circle
  /// with a 3px border, leaving about 104px of usable area, and the
  /// largest square that fits inside a circle without its corners
  /// being cut off is around 73px (104 / 1.414). The glyph sits
  /// comfortably below that at 56px, the usual avatar proportion, so
  /// no part of the icon's box ever reaches the circle's edge.
  Widget _buildDefaultAvatar() {
    return const ColoredBox(
      color: Color(0xFFFCEBEF),
      child: Center(
        child: Icon(
          Icons.person_rounded,
          size: 56,
          color: Color(0xFFC25E7A),
        ),
      ),
    );
  }

  /// Longest edge the picked image is resized to before upload.
  static const int _maxImageDimension = 512;

  bool _uploadingPicture = false;

  /// Both streams are created once in initState and recreated whenever
  /// the auth state flips. Building them inside `build` re-opened the
  /// realtime subscription on every rebuild, so they are kept in fields
  /// -- but they must be refreshed on sign in, because `watchOrders()`
  /// and `watchProfile()` return empty streams while signed out (there
  /// is no user id to filter on). This tab is built inside the
  /// IndexedStack at app start, i.e. while still signed out, so without
  /// the recreation in the auth listener the orders list and avatar stay
  /// blank forever after logging in.
  late Stream<List<Map<String, dynamic>>> _ordersStream;
  late Stream<Map<String, dynamic>?> _profileStream;

  void _refreshStreams() {
    _ordersStream = AppRepository.watchOrders();
    _profileStream = AppRepository.watchProfile();
  }

  /// Cached rather than read from `AppSession` during `build`.
  ///
  /// This tab lives in an IndexedStack, so it stays mounted behind the
  /// products tab. Reading the getter in `build` would leave the screen
  /// showing the signed in view after a logout, and would keep offering
  /// "Change Password" and "Log Out" to somebody who is not signed in.
  bool _isLoggedIn = false;

  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();

    _refreshStreams();

    _isLoggedIn = AppSession.isLoggedIn;

    _authSubscription =
        SupabaseService.client.auth.onAuthStateChange.listen((state) {
      final isLoggedIn = state.session != null;

      if (isLoggedIn == _isLoggedIn) return;
      if (!mounted) return;

      // Recreate the streams for the new auth state. Signed in, they
      // now carry the user's id and really subscribe; signed out, they
      // fall back to empty. Without this the tab keeps the empty streams
      // it built while signed out and never shows any orders or avatar.
      _refreshStreams();

      setState(() {
        _isLoggedIn = isLoggedIn;
      });
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  /// Shrinks the image so uploads stay fast and cheap.
  ///
  /// Always re-encodes to PNG, so the caller can rely on the bytes
  /// matching an `image/png` content type and a `.png` file name.
  Future<Uint8List> _resizeImage(Uint8List bytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(
      bytes,
    );

    // Disposed in `finally`: the codec holds the decoded frames and
    // would otherwise leak for the lifetime of the isolate.
    ui.Image? source;

    try {
      final ui.FrameInfo frame = await codec.getNextFrame();

      source = frame.image;

      final longestSide = source.width > source.height
          ? source.width
          : source.height;

      if (longestSide <= _maxImageDimension) {
        final pngBytes = await source.toByteData(
          format: ui.ImageByteFormat.png,
        );

        return _pngBytesOrThrow(pngBytes);
      }

      final scale = _maxImageDimension / longestSide;

      final resizedWidth = (source.width * scale).round();
      final resizedHeight = (source.height * scale).round();

      final recorder = ui.PictureRecorder();

      final canvas = Canvas(recorder);

      canvas.drawImageRect(
        source,
        Rect.fromLTWH(
          0,
          0,
          source.width.toDouble(),
          source.height.toDouble(),
        ),
        Rect.fromLTWH(
          0,
          0,
          resizedWidth.toDouble(),
          resizedHeight.toDouble(),
        ),
        Paint(),
      );

      final ui.Picture picture = recorder.endRecording();

      final ui.Image resized =
          await picture.toImage(resizedWidth, resizedHeight);

      try {
        final pngBytes = await resized.toByteData(
          format: ui.ImageByteFormat.png,
        );

        return _pngBytesOrThrow(pngBytes);
      } finally {
        resized.dispose();
        picture.dispose();
      }
    } finally {
      source?.dispose();
      codec.dispose();
    }
  }

  /// Guards the two `toByteData` results above.
  ///
  /// Encoding to PNG can, in rare cases on some platforms, return null.
  /// Turning that into a thrown StateError surfaces it in the catch block
  /// as a readable message rather than a null-check crash.
  static Uint8List _pngBytesOrThrow(ByteData? pngBytes) {
    if (pngBytes == null) {
      throw StateError('Could not encode the image.');
    }

    return pngBytes.buffer.asUint8List();
  }

  /// Uploads the picked image to the public "avatars" bucket and
  /// stores the resulting public URL on the profile row.
  Future<void> _pickProfilePicture() async {
    final ImagePicker picker = ImagePicker();

    XFile? pickedFile;

    // The picker call is inside the try block so a platform or plugin
    // failure shows a message instead of crashing the screen.
    try {
      pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
      );
    } on MissingPluginException {
      // Means the native plugin is not registered yet, usually from a
      // hot reload instead of a full restart.
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Image picker is unavailable. "
            "Please fully restart the app.",
          ),
        ),
      );

      return;
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Could not open the gallery: $e"),
        ),
      );

      return;
    }

    if (pickedFile == null) return;
    if (!mounted) return;

    final userId = AppSession.userId;

    if (userId == null) return;

    setState(() {
      _uploadingPicture = true;
    });

    try {
      final bytes = await pickedFile.readAsBytes();
      final resized = await _resizeImage(bytes);

      // Fixed name per user; always PNG because we re-encode. Path is
      // relative to the `avatars` bucket root (not prefixed with the
      // bucket name, which would create an `avatars/` subfolder).
      final path = '$userId.png';
      final legacyPath = 'avatars/$userId.png';

      // Remove current + legacy (double-prefixed) location so the bucket
      // doesn't accumulate orphaned files across path format changes.
      await SupabaseService.client.storage
          .from(_avatarBucket)
          .remove([path, legacyPath]);

      await SupabaseService.client.storage
          .from(_avatarBucket)
          .uploadBinary(
            path,
            resized,
            fileOptions: const FileOptions(
              contentType: 'image/png',
              upsert: true,
            ),
          );

      final publicUrl = SupabaseService.client.storage
          .from(_avatarBucket)
          .getPublicUrl(path);

      // Cache-bust: storage path is fixed (overwritten), so the base URL
      // stays the same and image caches (disk + in-memory/CDN) would keep
      // serving the old photo. Saving a versioned URL makes the profile
      // stream emit a changed value and forces a fresh fetch.
      final versionedUrl = Uri.parse(publicUrl)
          .replace(
            queryParameters: {
              'v': DateTime.now().millisecondsSinceEpoch.toString(),
            },
          )
          .toString();

      await AppRepository.updateProfileImage(versionedUrl);

      // Best-effort eviction of the base URL from the disk cache.
      await TouchSkinCacheManager.instance.removeFile(publicUrl);
      await TouchSkinCacheManager.instance.removeFile(versionedUrl);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Profile picture updated."),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Could not update picture: $e"),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _uploadingPicture = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    await SessionPersistence.clear();
    await SupabaseService.client.auth.signOut();

    if (!mounted) return;

    // Drop every pushed route (cart, checkout, product pages) and land
    // back on the home Dashboard, where the customer can keep browsing
    // as a guest. Navigating to LoginScreen here was a dead end: it had
    // no back button and no route beneath it, so the only way out of it
    // was to sign in again or kill the app.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  String _formatCurrency(dynamic amount) =>
      CurrencyFormat.php(CurrencyFormat.parse(amount));

  Widget _buildProfileCard(String? profileImageUrl) {
    final hasCustomPicture =
        profileImageUrl != null && profileImageUrl.isNotEmpty;

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
        children: [
          GestureDetector(
            onTap: _uploadingPicture
                ? null
                : _pickProfilePicture,

            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  width: 110,
                  height: 110,

                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFFCEBEF),
                  ),

                  clipBehavior: Clip.antiAlias,

                  // The ring is painted on top of the photo rather than
                  // around it. A border on the outer decoration insets
                  // the image box by the border width, so any mismatch
                  // between the picture and the circle showed as a
                  // blush crescent under the ring. Overlapping the
                  // edge is what makes the photo read as a full circle.
                  foregroundDecoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFC25E7A),
                      width: 3,
                    ),
                  ),

                  child: _uploadingPicture
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFFC25E7A),
                          ),
                        )
                      : hasCustomPicture
                          ? Transform.scale(
                              // A touch of zoom so any background the
                              // source picture carries around its own
                              // edge -- avatars saved from other apps
                              // are often a circular photo on a
                              // coloured square -- falls outside the
                              // clip instead of peeking out along the
                              // rim. Small enough to go unnoticed on
                              // an ordinary photo.
                              scale: 1.15,

                              child: CachedNetworkImage(
                                imageUrl: profileImageUrl,
                                fit: BoxFit.cover,
                                cacheManager:
                                    TouchSkinCacheManager.instance,

                                placeholder: (context, url) {
                                  return _buildDefaultAvatar();
                                },

                                errorWidget: (context, url, error) {
                                  return _buildDefaultAvatar();
                                },
                              ),
                            )
                          : _buildDefaultAvatar(),
                ),

                Positioned(
                  right: 0,
                  bottom: 0,

                  child: Container(
                    padding: const EdgeInsets.all(6),

                    decoration: const BoxDecoration(
                      color: Color(0xFFC25E7A),
                      shape: BoxShape.circle,

                      // No white outline here on purpose. The badge
                      // and the avatar ring are the same blue, so a
                      // white border punched a visible gap into the
                      // ring where the two overlap, which made the
                      // circle look broken.
                    ),

                    child: const Icon(
                      Icons.photo_camera_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          Text(
            AppSession.username ?? "Guest",
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            hasCustomPicture
                ? "Tap the photo to change it."
                : "Tap the photo to add your picture.",
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),

          const SizedBox(height: 18),

          SizedBox(
            width: double.infinity,
            height: 50,

            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CartScreen(),
                  ),
                );
              },

              icon: const Icon(Icons.shopping_cart_rounded),

              label: const Text(
                "View My Cart",
                style: TextStyle(fontWeight: FontWeight.bold),
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

  Widget _buildEmptyOrders() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),

      child: const Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 56,
            color: Colors.grey,
          ),

          SizedBox(height: 12),

          Text(
            "No orders yet.",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),

          SizedBox(height: 6),

          Text(
            "Your purchases will appear here.",
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItem(
    String orderId,
    Map<String, dynamic> order,
  ) {
    final createdAt = order["created_at"];

    String dateLabel = "Date unavailable";

    if (createdAt is String && createdAt.isNotEmpty) {
      final parsed = DateTime.tryParse(createdAt);

      if (parsed != null) {
        dateLabel = DateFormat("MMM d, yyyy - h:mm a")
            .format(parsed.toLocal());
      }
    }

    final status = readOrderStatus(order["status"]);
    final isCancelled = status.isCancelled;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OrderDetailScreen(
              orderId: orderId,
            ),
          ),
        );
      },

      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),

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

      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,

            decoration: BoxDecoration(
              color: status.background,
              borderRadius: BorderRadius.circular(14),
            ),

            child: Icon(
              status.icon,
              color: status.color,
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  "${status.label} \u00b7 ${order["payment_method"] ?? "N/A"}",
                  style: TextStyle(
                    color: status.color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          Text(
            _formatCurrency(order["total_amount"]),
            style: TextStyle(
              color: isCancelled
                  ? Colors.grey
                  : const Color(0xFFC25E7A),
              fontWeight: FontWeight.bold,
              decoration: isCancelled
                  ? TextDecoration.lineThrough
                  : null,
            ),
          ),

          const SizedBox(width: 8),

          const Icon(
            Icons.chevron_right_rounded,
            color: Colors.grey,
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildOrders() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _ordersStream,

      builder: (context, snapshot) {
        if (snapshot.connectionState ==
            ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFFC25E7A),
            ),
          );
        }

        final orders = snapshot.data ?? const [];

        if (orders.isEmpty) {
          return _buildEmptyOrders();
        }

        return Column(
          children: orders
              .map(
                (order) => _buildOrderItem(
                  order["id"]?.toString() ?? "",
                  order,
                ),
              )
              .toList(),
        );
      },
    );
  }

  void _openLogin() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const LoginScreen(),
      ),
    );
  }

  /// Shown in place of the account view when nobody is signed in.
  ///
  /// The profile card, the order list and the Change Password button all
  /// describe a signed in person, and a Log Out button offered to
  /// somebody with no session does nothing useful. So the whole body is
  /// swapped rather than the buttons being hidden one by one.
  Widget _buildSignedOut() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),

        child: Column(
          mainAxisSize: MainAxisSize.min,

          children: [
            Container(
              width: 84,
              height: 84,

              decoration: const BoxDecoration(
                color: Color(0xFFFCEBEF),
                shape: BoxShape.circle,
              ),

              child: const Icon(
                Icons.person_off_rounded,
                size: 40,
                color: Color(0xFFC25E7A),
              ),
            ),

            const SizedBox(height: 18),

            const Text(
              "You're not signed in",
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              "Log in to see your profile, track your orders and check out faster.",
              textAlign: TextAlign.center,

              style: TextStyle(
                color: Colors.grey,
                fontSize: 13,
                height: 1.4,
              ),
            ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 52,

              child: ElevatedButton.icon(
                onPressed: _openLogin,

                icon: const Icon(Icons.login_rounded),

                label: const Text(
                  "Log In",
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

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              height: 48,

              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          const CreateAccountScreen(),
                    ),
                  );
                },

                icon: const Icon(Icons.person_add_alt_rounded, size: 18),

                label: const Text(
                  "Create an account",
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),

                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFC25E7A),
                  side: const BorderSide(color: Color(0xFFC25E7A)),

                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // No greeting to greet with when there is no account, so the
    // header says something true instead of "Welcome, ".
    final username = AppSession.username;

    return Column(
      children: [
        GradientHeader(
          toolbarTitle: "My Account",
          headerTitle: _isLoggedIn
              ? "Welcome, $username"
              : "Welcome",
          subtitle: _isLoggedIn
              ? "Manage your profile and orders."
              : "Log in to manage your profile and orders.",
          icon: _isLoggedIn
              ? Icons.person_rounded
              : Icons.person_outline_rounded,
        ),

        Expanded(
          child: _isLoggedIn
              ? _buildSignedInBody()
              : _buildSignedOut(),
        ),
      ],
    );
  }

  Widget _buildSignedInBody() {
    // The footer overlays the bottom of the page (Scaffold
    // extendBody), so the last buttons need room to scroll above it:
    // the NavigationBar's 68px plus the home-indicator inset its
    // SafeArea reserves, on top of the original 16px.
    final footerReserve =
        16 + 68 + MediaQuery.of(context).padding.bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, footerReserve),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
                StreamBuilder<Map<String, dynamic>?>(
                  stream:
                      _profileStream,

                  builder: (context, snapshot) {
                    final profile = snapshot.data;

                    String? profileImageUrl;

                    if (profile != null) {
                      final image = profile["profile_image"];

                      if (image is String && image.isNotEmpty) {
                        profileImageUrl = image;
                      }
                    }

                    return _buildProfileCard(profileImageUrl);
                  },
                ),

                const SizedBox(height: 20),

                Row(
                  children: [
                    const Text(
                      "My Orders",
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
                        borderRadius:
                            BorderRadius.circular(20),
                      ),

                      child: const Row(
                        children: [
                          Icon(
                            Icons.history_rounded,
                            size: 15,
                            color: Color(0xFFC25E7A),
                          ),

                          SizedBox(width: 4),

                          Text(
                            "History",
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

                const SizedBox(height: 12),

                _buildOrders(),

                const SizedBox(height: 18),

                // Change password
                SizedBox(
                  width: double.infinity,
                  height: 52,

                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const ChangePasswordScreen(),
                        ),
                      );
                    },

                    icon: const Icon(
                      Icons.password_rounded,
                    ),

                    label: const Text(
                      "Change Password",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFC25E7A),
                      side: const BorderSide(
                        color: Color(0xFFC25E7A),
                      ),

                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  height: 52,

                  child: OutlinedButton.icon(
                    onPressed: _logout,

                    icon: const Icon(Icons.logout_rounded),

                    label: const Text(
                      "Log Out",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(
                        color: Colors.redAccent,
                      ),

                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 14),
        ],
      ),
    );
  }
}
