import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/session/buffering_overlay.dart';

void main() {
  testWidgets('BufferingOverlay shows message and detail', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BufferingOverlay(
            message: 'Connecting',
            detail: 'lab:5901',
          ),
        ),
      ),
    );
    expect(find.text('Connecting'), findsOneWidget);
    expect(find.text('lab:5901'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
