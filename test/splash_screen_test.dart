import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_mobile/splash_screen.dart';

/// The splash is pure presentation: Supabase is initialized in main()
/// before the first frame, and the screen only gates the minimum brand
/// time before replacing itself with the storefront.
///
/// The test steps frames by hand rather than calling pumpAndSettle --
/// the logo pulse and the dot loader repeat forever, so settling would
/// never return. Ending on a shrink wrapper disposes the state, which
/// cancels the navigation timer and the two tickers.
void main() {
  testWidgets('the splash shows the brand, logo and loader', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SplashScreen()),
    );

    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(find.text('TouchSkin'), findsOneWidget);
    expect(find.text('SKINCARE, CURATED FOR YOU'), findsOneWidget);
    expect(find.text('Preparing your shelf…'), findsOneWidget);

    // The logo card, and no bare spinner: the loader is the dots.
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // 600ms pumped so far, still under the 850ms gate.
    expect(find.byType(SplashScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
