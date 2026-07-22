import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/library/chrome_tab_strip.dart';
import 'package:helmhost/session/open_session_registry.dart';
import 'package:helmhost/session/session_link_stats.dart';
import 'package:helmhost/session/session_overview.dart';

void main() {
  OpenSessionRef tab(int id, String host) => OpenSessionRef(
        id: id,
        host: host,
        port: 5900,
        shell: SessionShell.tabs,
      );

  testWidgets('strip shows Library and selects tab', (tester) async {
    var selected = 0;
    var libToggles = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChromeTabStrip(
            sessions: [tab(1, 'a.example')],
            activeSessionId: 1,
            libraryOverlayOpen: false,
            onToggleLibrary: () => libToggles++,
            onSelect: (id) => selected = id,
            onClose: (_) {},
            onDetach: (_) {},
            onNewConnection: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    await tester.tap(find.byKey(const Key('library-toggle')));
    expect(libToggles, 1);
    await tester.tap(find.text('A'));
    expect(selected, 1);
  });

  testWidgets('overflow with many tabs does not throw', (tester) async {
    final sessions = [for (var i = 0; i < 10; i++) tab(i + 1, 'h$i')];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChromeTabStrip(
            sessions: sessions,
            activeSessionId: 1,
            libraryOverlayOpen: false,
            onToggleLibrary: () {},
            onSelect: (_) {},
            onClose: (_) {},
            onDetach: (_) {},
            onNewConnection: (_) {},
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('chrome-tab-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('+ sits immediately after last tab not far right', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            child: ChromeTabStrip(
              sessions: [tab(1, 'a.example')],
              activeSessionId: 1,
              libraryOverlayOpen: false,
              onToggleLibrary: () {},
              onSelect: (_) {},
              onClose: (_) {},
              onDetach: (_) {},
              onNewConnection: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('chrome-tab-new')), findsOneWidget);
    final tabLeft = tester.getTopLeft(find.text('A')).dx;
    final plusLeft =
        tester.getTopLeft(find.byKey(const Key('chrome-tab-new'))).dx;
    final stripRight = tester.getBottomRight(find.byType(ChromeTabStrip)).dx;
    expect(plusLeft, greaterThan(tabLeft));
    // Not pinned to the far right of a wide strip.
    expect(plusLeft, lessThan(stripRight - 120));
  });

  testWidgets('hover shows overview then clears on exit', (tester) async {
    final stats = SessionLinkStats();
    stats.recordFrame();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChromeTabStrip(
            sessions: [tab(1, 'grog')],
            activeSessionId: 1,
            libraryOverlayOpen: false,
            overviews: {
              1: SessionOverviewData(
                host: 'grog',
                port: 5901,
                connState: SessionConnState.live,
                linkStats: stats,
                bandwidthLabel: 'Balanced',
                width: 100,
                height: 50,
              ),
            },
            onToggleLibrary: () {},
            onSelect: (_) {},
            onClose: (_) {},
            onDetach: (_) {},
            onNewConnection: (_) {},
          ),
        ),
      ),
    );
    final gesture =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.text('Grog')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('tab-overview-card')), findsOneWidget);
    expect(find.textContaining('Update rate:'), findsOneWidget);
    await gesture.moveTo(const Offset(0, 0));
    await tester.pump();
    expect(find.byKey(const Key('tab-overview-card')), findsNothing);
  });

  testWidgets('+ menu invokes callback with profile id', (tester) async {
    String? chosen = 'sentinel';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChromeTabStrip(
            sessions: [tab(1, 'a.example')],
            activeSessionId: 1,
            libraryOverlayOpen: false,
            profiles: const [
              (id: 'p-lab', label: 'Lab'),
              (id: 'p-work', label: 'Work'),
            ],
            onToggleLibrary: () {},
            onSelect: (_) {},
            onClose: (_) {},
            onDetach: (_) {},
            onNewConnection: (id) => chosen = id,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('chrome-tab-new')));
    await tester.pumpAndSettle();
    expect(find.text('New connection…'), findsOneWidget);
    expect(find.text('Add under Lab…'), findsOneWidget);
    await tester.tap(find.text('Add under Lab…'));
    await tester.pumpAndSettle();
    expect(chosen, 'p-lab');

    chosen = 'sentinel';
    await tester.tap(find.byKey(const Key('chrome-tab-new')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New connection…'));
    await tester.pumpAndSettle();
    expect(chosen, isNull);
  });
}
