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

  const favoriteCard = LibraryCard(
    id: 'fav:5900',
    host: 'fav.example',
    port: 5900,
    displayName: 'Fav',
    favorite: true,
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

  test('Small footer padding is smaller than Medium', () {
    final small = libraryGridFooterPadding(LibraryGridSize.small);
    final medium = libraryGridFooterPadding(LibraryGridSize.medium);
    expect(small.top, lessThan(medium.top));
    expect(small.bottom, lessThan(medium.bottom));
  });

  test('libraryCardFooterPadding matches libraryGridFooterPadding', () {
    for (final size in LibraryGridSize.values) {
      expect(
        libraryCardFooterPadding(size),
        equals(libraryGridFooterPadding(size)),
      );
    }
  });

  testWidgets('LibraryGridCard shows favorite star', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 280,
            child: LibraryGridCard(
              card: favoriteCard,
              onTap: () {},
              onAction: (_, __) async {},
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.star), findsOneWidget);
  });

  testWidgets('LibraryGridCard selecting=true shows Checkbox', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 280,
            child: LibraryGridCard(
              card: card,
              onTap: () {},
              onAction: (_, __) async {},
              selecting: true,
              selected: false,
              onSelectedChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.byType(Checkbox), findsOneWidget);
  });

  testWidgets('LibraryGridCard tap body in selecting mode calls onSelectedChanged(true)',
      (tester) async {
    bool? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 280,
            child: LibraryGridCard(
              card: card,
              onTap: () {},
              onAction: (_, __) async {},
              selecting: true,
              selected: false,
              onSelectedChanged: (v) => changed = v,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Lab'));
    await tester.pumpAndSettle();
    expect(changed, isTrue);
  });

  testWidgets('LibraryGridCard pin/unpin in menu', (tester) async {
    String? action;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 280,
            child: LibraryGridCard(
              card: card,
              onTap: () {},
              onAction: (a, _) async => action = a,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin'));
    await tester.pumpAndSettle();
    expect(action, 'pin');
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

  testWidgets('LibraryListTile shows favorite star', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryListTile(
            card: favoriteCard,
            onTap: () {},
            onAction: (_, __) async {},
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.star), findsOneWidget);
  });
}
