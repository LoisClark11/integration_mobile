import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// App-level session persistence policy layered on top of Supabase Auth.
///
/// Supabase persists the auth session across restarts (`persistSession: true`).
/// This class adds an inactivity limit: if the app has not been opened for an
/// extended period, the stored session is cleared on next launch so the user
/// must sign in again. Clearing app data also removes the session (handled by
/// the OS/storage).
class SessionPersistence {
  SessionPersistence._();

  static const String _lastActiveKey = 'touchskin_last_active_ms';

  /// How long a user can stay "remembered" without opening the app.
  static const Duration inactivityLimit = Duration(days: 30);

  /// Records "now" as the last time the app was actively used while signed in.
  static Future<void> markActive() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastActiveKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // Best-effort; never block auth/app startup.
    }
  }

  /// Clears the activity marker (call on explicit sign-out).
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastActiveKey);
    } catch (_) {
      // Best-effort.
    }
  }

  /// Enforces the inactivity limit for a restored session.
  ///
  /// Call after [Supabase.initialize]. If a session exists but the app was
  /// last opened beyond [inactivityLimit], signs out. Otherwise records
  /// activity so the "last opened" window stays current.
  static Future<void> checkAndEnforce() async {
    try {
      final auth = Supabase.instance.client.auth;
      final session = auth.currentSession;
      if (session == null) {
        // No restored session; keep any marker harmlessly or leave as-is.
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final lastMs = prefs.getInt(_lastActiveKey);
      final now = DateTime.now();

      if (lastMs != null) {
        final lastActive = DateTime.fromMillisecondsSinceEpoch(lastMs);
        if (now.difference(lastActive) > inactivityLimit) {
          await auth.signOut();
          await prefs.remove(_lastActiveKey);
          return;
        }
      }

      // Session present and within limit (or no marker yet): treat as active.
      await prefs.setInt(_lastActiveKey, now.millisecondsSinceEpoch);
    } catch (_) {
      // Never block startup on a persistence-policy error.
    }
  }
}
