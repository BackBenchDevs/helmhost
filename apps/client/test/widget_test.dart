import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost_client/main.dart';

void main() {
  testWidgets('Library shows Helmhost title', (tester) async {
    await tester.pumpWidget(const HubApp());
    expect(find.text('Helmhost'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
  });
}
