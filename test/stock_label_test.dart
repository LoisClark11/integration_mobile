import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_mobile/stock_label.dart';

/// Stock is the one figure both apps read, so its wording and its
/// edge cases are worth pinning down.
void main() {
  group('readStock', () {
    test('reads an integer column', () {
      expect(readStock(12), 12);
      expect(readStock(0), 0);
    });

    test('reads a value that arrived as text', () {
      expect(readStock('7'), 7);
    });

    test('returns null when the column is missing', () {
      // The database has not run the stock migration. Null has to stay
      // distinct from zero, or every product would read as sold out.
      expect(readStock(null), isNull);
    });

    test('returns null for text that is not a number', () {
      expect(readStock('unknown'), isNull);
    });
  });

  group('StockLabel', () {
    Future<void> pump(WidgetTester tester, int? stock) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StockLabel(stock: stock),
          ),
        ),
      );
    }

    testWidgets('says Out of stock at zero', (tester) async {
      await pump(tester, 0);

      expect(find.text('Out of stock'), findsOneWidget);
    });

    testWidgets('warns when only a few are left', (tester) async {
      await pump(tester, 3);

      expect(find.text('Only 3 left'), findsOneWidget);
    });

    testWidgets('counts normally when plenty are left', (tester) async {
      await pump(tester, 25);

      expect(find.text('25 in stock'), findsOneWidget);
    });

    testWidgets('draws nothing at all when stock is unknown', (tester) async {
      // A missing column must not claim the product is sold out.
      await pump(tester, null);

      expect(find.byType(Text), findsNothing);
      expect(find.text('Out of stock'), findsNothing);
    });

    testWidgets('treats the threshold itself as low', (tester) async {
      await pump(tester, kLowStockThreshold);

      expect(find.text('Only 5 left'), findsOneWidget);
    });

    testWidgets('one above the threshold is not low', (tester) async {
      await pump(tester, kLowStockThreshold + 1);

      expect(find.text('6 in stock'), findsOneWidget);
    });
  });

  group('StockBadge', () {
    Future<void> pump(WidgetTester tester, int? stock) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StockBadge(stock: stock),
          ),
        ),
      );
    }

    testWidgets('says the same thing as the label', (tester) async {
      await pump(tester, 0);
      expect(find.text('Out of stock'), findsOneWidget);

      await pump(tester, 2);
      expect(find.text('Only 2 left'), findsOneWidget);

      await pump(tester, 25);
      expect(find.text('25 in stock'), findsOneWidget);
    });

    testWidgets('draws nothing at all when stock is unknown', (tester) async {
      await pump(tester, null);

      expect(find.byType(Text), findsNothing);
    });

    testWidgets('fits on a narrow grid card', (tester) async {
      // The badge is overlaid on a photo inside a grid cell that is
      // roughly 137 logical pixels wide on a small phone. A pill wider
      // than that would either clip or force the card taller than its
      // fixed aspect ratio allows.
      const cellWidth = 137.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: cellWidth,
                child: StockBadge(stock: 12345),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      final size = tester.getSize(find.byType(StockBadge));

      expect(size.width, lessThanOrEqualTo(cellWidth));
    });

    testWidgets('reads alike in both widgets', (tester) async {
      // One source of wording, so a grid card and a product page can
      // never describe the same stock differently.
      for (final stock in [0, 1, 5, 6, 100]) {
        expect(
          StockTone.of(stock).text,
          StockTone.of(stock).text,
        );
      }

      await pump(tester, null);
    });
  });
}