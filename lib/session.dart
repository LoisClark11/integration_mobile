import 'package:supabase_flutter/supabase_flutter.dart';

/// Read-only view over the signed in user.
///
/// Supabase Auth keeps the authoritative session, so nothing is cached
/// or written here. Every value is read straight from the client, which
/// means a sign in or sign out is reflected immediately and a cold
/// start behaves exactly like a warm one.
class AppSession {
  static bool get isLoggedIn =>
      Supabase.instance.client.auth.currentSession != null;

  /// Auth user id. This is the `user_id` used by every table.
  static String? get userId {
    final user = Supabase.instance.client.auth.currentUser;

    return user?.id;
  }

  /// Display name shown in the profile page.
  static String? get username {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) return null;

    final metadataName =
        user.userMetadata?['username']?.toString();

    if (metadataName != null && metadataName.isNotEmpty) {
      return metadataName;
    }

    final email = user.email;

    if (email == null || email.isEmpty) return null;

    return email.split('@').first;
  }

  static String? get email =>
      Supabase.instance.client.auth.currentUser?.email;
}