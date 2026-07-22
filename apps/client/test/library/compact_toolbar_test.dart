import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/library/compact_toolbar.dart';

void main() {
  testWidgets('CompactToolbar shows hint and Connect invokes callback',
      (tester) async {
    var connected = false;
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompactToolbar(
            controller: controller,
            onConnect: () => connected = true,
          ),
        ),
      ),
    );
    expect(find.text('VNC address or search…'), findsOneWidget);
    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(connected, isTrue);
  });
}
