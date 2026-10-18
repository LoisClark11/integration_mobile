import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_mobile/user_profile_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The profile tab is mounted inside an IndexedStack, so it survives a
/// logout and a login. These tests pin the state it is meant to show in
/// each case, which used to be wrong in both directions: a signed out
/// visitor was offered Change Password and Log Out, and a signed in
/// customer stayed on that screen after signing out.
void main() {
  setUpAll(() async {
    // The screen reads AppSession, which goes through the Supabase
    // client, so the client has to exist. Pointing it at the discard
    // port means any request fails immediately and offline instead of
    // hanging on a real network call, and with no stored session every
    // test starts signed out.
    TestWidgetsFlutterBinding.ensureInitialized();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (call) async => <String, Object?>{},
    );

    await Supabase.initialize(
      url: 'http://127.0.0.1:9',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(
        persistSession: false,
        autoRefreshToken: false,
      ),
    );
  });

  Future<void> pumpProfile(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UserProfileScreen(),
        ),
      ),
    );
  }

  testWidgets('a signed out visitor gets Log In, not Log Out', (tester) async {
    await pumpProfile(tester);

    expect(find.text("Log In"), findsOneWidget);

    // These described a signed in person, and doing nothing useful for
    // somebody with no session.
    expect(find.text("Log Out"), findsNothing);
    expect(find.text("Change Password"), findsNothing);
  });

  testWidgets('explains why the account view is empty', (tester) async {
    await pumpProfile(tester);

    expect(find.text("You're not signed in"), findsOneWidget);
  });

  testWidgets('does not greet a signed out visitor by name', (tester) async {
    await pumpProfile(tester);

    // AppSession.username is null here, so the old code rendered the
    // literal string "Welcome, ".
    expect(find.textContaining("Welcome,"), findsNothing);
  });

  testWidgets('does not show an empty profile card or order list', (
    tester,
  ) async {
    await pumpProfile(tester);

    // The avatar card and "No orders yet" both describe an account.
    expect(find.text("My Orders"), findsNothing);
  });

  testWidgets('offers a way to sign up', (tester) async {
    await pumpProfile(tester);

    expect(find.text("Create an account"), findsOneWidget);
  });
}