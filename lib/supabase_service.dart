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
  /// `persistSession: false` is what makes the app forget a signed in
  /// user on restart. Left on, Supabase writes the session to shared
  /// preferences and restores it on the next cold start, so closing and
  /// reopening the app drops the customer straight back onto the
  /// products page as somebody who never chose to sign in again.
  ///
  /// Turning it off swaps that store for `EmptyLocalStorage`, so the
  /// session lives in memory for as long as the process does and is gone
  /// the next time the app starts.
  ///
  /// `autoRefreshToken: true` keeps that in-memory session valid. An
  /// access token expires after about an hour; without a refresh every
  /// query and write starts failing with 401 while the UI still shows
  /// the customer as signed in. Refreshing only touches the token in
  /// memory -- nothing is written to disk -- so it does not weaken the
  /// cold-start-is-signed-out behaviour above.
  ///
  /// The password reset link still works. That flow arrives as a deep
  /// link, and `detectSessionInUri` still exchanges it for a session in
  /// memory during that run, which is all `ResetPasswordScreen` needs.
  static Future<void> initialize() async {
    if (_initialized) return;

    await Supabase.initialize(
      url: projectUrl,
      publishableKey: publishableKey,
      authOptions: const FlutterAuthClientOptions(
        persistSession: false,
        autoRefreshToken: true,
      ),
    );

    _initialized = true;
  }

  static SupabaseClient get client => Supabase.instance.client;
}