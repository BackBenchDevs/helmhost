import 'package:flutter_test/flutter_test.dart';

/// Taps a popup menu item by label without triggering hit-test warnings.
Future<void> tapMenuItem(WidgetTester tester, String label) async {
  final finder = find.text(label).last;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder, warnIfMissed: false);
  await tester.pumpAndSettle();
}
