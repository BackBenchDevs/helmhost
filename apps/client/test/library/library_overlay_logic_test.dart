import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/library/library_overlay_sidebar.dart';

void main() {
  group('shouldUseLibraryOverlay', () {
    test('true only when sessions and open', () {
      expect(
        shouldUseLibraryOverlay(sessionCount: 1, overlayOpen: true),
        isTrue,
      );
      expect(
        shouldUseLibraryOverlay(sessionCount: 0, overlayOpen: true),
        isFalse,
      );
      expect(
        shouldUseLibraryOverlay(sessionCount: 2, overlayOpen: false),
        isFalse,
      );
    });
  });

  group('hubWindowTitle / addressForTab', () {
    test('formats title and address', () {
      expect(hubWindowTitle(empty: true), 'HelmHost');
      expect(
        hubWindowTitle(host: 'a', port: 5900, empty: false),
        'a:5900',
      );
      expect(addressForTab('grog', 5901), 'grog:5901');
    });
  });

  group('shouldShowHubLibraryStatusBar', () {
    test('hidden when tabs have sessions', () {
      expect(
        shouldShowHubLibraryStatusBar(useTabs: true, sessionCount: 1),
        isFalse,
      );
      expect(
        shouldShowHubLibraryStatusBar(useTabs: true, sessionCount: 0),
        isTrue,
      );
      expect(
        shouldShowHubLibraryStatusBar(useTabs: false, sessionCount: 5),
        isTrue,
      );
    });
  });

  testWidgets('scaffold bottom bar would shrink; helper prevents swap',
      (tester) async {
    // Regression: adding LibraryStatusBar to Scaffold shrinks body — hub must
    // keep bottomNavigationBar null when sessions exist (helper == false).
    expect(
      shouldShowHubLibraryStatusBar(useTabs: true, sessionCount: 2),
      isFalse,
    );

    Size? withBar;
    Size? withoutBar;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(
            child: ColoredBox(key: Key('body'), color: Colors.red),
          ),
          bottomNavigationBar: const SizedBox(
            height: 26,
            child: ColoredBox(color: Colors.green),
          ),
        ),
      ),
    );
    withBar = tester.getSize(find.byKey(const Key('body')));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: ColoredBox(key: Key('body'), color: Colors.red),
          ),
        ),
      ),
    );
    withoutBar = tester.getSize(find.byKey(const Key('body')));
    expect(withBar.height, lessThan(withoutBar.height));
  });

  testWidgets('overlay keeps session size; scrim dismisses', (tester) async {
    var dismissed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(
                  key: Key('session-underlay'),
                  color: Colors.blue,
                ),
                LibraryOverlaySidebar(
                  onDismiss: () => dismissed = true,
                  child: const Center(child: Text('Library panel')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final before = tester.getSize(find.byKey(const Key('session-underlay')));
    expect(find.byKey(const Key('library-overlay-panel')), findsOneWidget);
    expect(find.byKey(const Key('library-overlay-scrim')), findsOneWidget);
    final after = tester.getSize(find.byKey(const Key('session-underlay')));
    expect(after, before);
    await tester.tap(find.byKey(const Key('library-overlay-scrim')));
    expect(dismissed, isTrue);
  });

  testWidgets('overlay bottomBar stays in panel; underlay size unchanged',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(
                  key: Key('session-underlay'),
                  color: Colors.blue,
                ),
                LibraryOverlaySidebar(
                  onDismiss: () {},
                  bottomBar: const Text('footer', key: Key('footer')),
                  child: const Center(child: Text('Library panel')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final before = tester.getSize(find.byKey(const Key('session-underlay')));
    expect(find.byKey(const Key('library-overlay-panel')), findsOneWidget);
    expect(find.byKey(const Key('footer')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('library-overlay-panel')),
        matching: find.byKey(const Key('footer')),
      ),
      findsOneWidget,
    );
    final after = tester.getSize(find.byKey(const Key('session-underlay')));
    expect(after, before);
  });

  testWidgets('zero sessions path has no scrim when only library body',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Full library')),
        ),
      ),
    );
    expect(find.byKey(const Key('library-overlay-scrim')), findsNothing);
    expect(find.text('Full library'), findsOneWidget);
  });
}
