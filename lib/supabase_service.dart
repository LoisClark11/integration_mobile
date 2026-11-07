import 'package:supabase_flutter/supabase_flutter.dart';

/// Holds the single Supabase client used across the app.
///
/// The URL and publishable key live here. On Android this is where you paste
/// the values from Supabase -> Project Settings -> API.
///
/// The publishable key is safe to ship inside an app; it is designed to be
/// public and is protected by the row level security policies in
/// `supabase/schema.sql`. Never put the `secret` key here, because it
/// bypasses those policies entirely.
class SupabaseService {
  SupabaseService._();

  static const String projectUrl =
      'https://twuududkiejomeyskpnw.supabase.co';

  static const String publishableKey =
      'sb_publishable_1qZIq8fVvT2lVpvKV8DDeA_5pi_2oik';

  static bool _initialized = false;

  /// Where Supabase sends the user after clicking the reset link.
  ///
  /// The scheme and host here must match the `<intent-filter>` in
  /// `android/app/src/main/AndroidManifest.xml`, and the same URL must
  /// be listed under Authentication -> URL Configuration -> Redirect
  /// URLs in the Supabase dashboard. Supabase silently refuses to
  /// redirect to a target that is not allow listed.
  static const String deepLinkRedirect =
      'integrationmobile://reset-password';

  /// Initializes the client once, before `runApp`.
  ///
  /// `persistSession` is enabled so a signed-in user stays signed in
  /// across cold starts. Clearing app data removes the stored session,
  /// and [SessionPersistence] signs the user out if the app has not
  /// been opened for an extended period.
  ///
  /// `autoRefreshToken: true` keeps the session valid while the app is
  /// in use (access tokens expire ~hourly). The password reset deep link
  /// still works: `detectSessionInUri` exchanges it for a session.
  static Future<void> initialize() async {
    if (_initialized) return;

    await Supabase.initialize(
      url: projectUrl,
      publishableKey: publishableKey,
      authOptions: const FlutterAuthClientOptions(
        persistSession: true,
        autoRefreshToken: true,
      ),
    );

    _initialized = true;
  }

  static SupabaseClient get client => Supabase.instance.client;
}