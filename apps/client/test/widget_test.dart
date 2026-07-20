import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost_client/main.dart';

void main() {
  testWidgets('Library shows title, Connect, empty saved', (tester) async {
    await tester.pumpWidget(const HubApp());
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Connect'), findsWidgets);
    expect(find.text('No saved connections yet'), findsOneWidget);
    expect(find.text('Saved connections'), findsOneWidget);
  });
}
