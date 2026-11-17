import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hen_price_app/main.dart';

// Runs every test on a phone-sized screen (360 x 800)
Future<void> pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MyApp());
  await tester.pumpAndSettle();
}

Future<void> tapPredict(WidgetTester tester) async {
  final button = find.text('Predict');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the title, 11 input fields and the Predict button', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('Hen Price Predictor'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(11));
    expect(find.text('Predict'), findsOneWidget);
    expect(find.text('Your estimated price will appear here'), findsOneWidget);
  });

  testWidgets(
    'an empty form shows a readable error instead of calling the API',
    (tester) async {
      await pumpApp(tester);

      await tapPredict(tester);

      expect(find.text('Check your input'), findsOneWidget);
      expect(find.text('Please select a province.'), findsOneWidget);
    },
  );

  testWidgets('Clear all resets the display area', (tester) async {
    await pumpApp(tester);
    await tapPredict(tester);
    expect(find.text('Check your input'), findsOneWidget);

    final clear = find.text('Clear all');
    await tester.ensureVisible(clear);
    await tester.pumpAndSettle();
    await tester.tap(clear);
    await tester.pumpAndSettle();

    expect(find.text('Check your input'), findsNothing);
    expect(find.text('Your estimated price will appear here'), findsOneWidget);
  });

  testWidgets(
    'province filters districts, district fills coordinates, wrong type is caught',
    (tester) async {
      await pumpApp(tester);

      // Pick Kigali City
      await tester.tap(find.byType(DropdownMenu<String>).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kigali City').last);
      await tester.pumpAndSettle();

      // The district list now only contains Kigali's three districts
      await tester.tap(find.byType(DropdownMenu<String>).at(1));
      await tester.pumpAndSettle();
      expect(find.text('Gasabo'), findsWidgets);
      expect(find.text('Musanze'), findsNothing);

      // Picking Gasabo fills in its latitude and longitude
      await tester.tap(find.text('Gasabo').last);
      await tester.pumpAndSettle();
      expect(find.text('-1.88'), findsOneWidget);
      expect(find.text('30.13'), findsOneWidget);

      // A month that is not a whole number is rejected before any API call
      await tester.enterText(
        find.widgetWithText(TextField, '2012 – 2030'),
        '2014',
      );
      await tester.enterText(find.widgetWithText(TextField, '1 – 12'), 'abc');
      await tapPredict(tester);

      expect(
        find.text('Month must be a whole number (you entered "abc").'),
        findsOneWidget,
      );
    },
  );
}
