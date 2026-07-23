import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/library/library_card_widgets.dart';
import 'package:helmhost/session_helpers.dart';

void main() {
  const card = LibraryCard(
    id: 'lab:5901',
    host: 'lab.example',
    port: 5901,
    displayName: 'Lab',
  );

  testWidgets('LibraryGridCard shows title and taps', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 280,
            child: LibraryGridCard(
              card: card,
              onTap: () => tapped = true,
              onAction: (_, __) async {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Lab'), findsOneWidget);
    await tester.tap(find.text('Lab'));
    expect(tapped, isTrue);
  });

  testWidgets('LibraryListTile shows title and menu actions', (tester) async {
    String? action;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryListTile(
            card: card,
            onTap: () {},
            onAction: (a, _) async => action = a,
          ),
        ),
      ),
    );
    expect(find.text('Lab'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(action, 'edit');
  });
}
