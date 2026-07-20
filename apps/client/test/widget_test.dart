import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost_client/main.dart';

void main() {
  testWidgets('Hub shows Helmhost title', (tester) async {
    await tester.pumpWidget(const HelmhostApp());
    expect(find.text('Helmhost'), findsOneWidget);
    expect(find.text('Hub'), findsOneWidget);
  });
}
