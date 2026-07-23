import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/gen/app_version.dart';
import 'package:helmhost/session/session_link_stats.dart';
import 'package:helmhost/session/session_status_bar.dart';
import 'package:helmhost/session_helpers.dart';
import 'package:helmhost/ui/app_about.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('sessionDisposeNotifiesHub', () {
    test('embedded soft dispose does not notify hub', () {
      expect(sessionDisposeNotifiesHub(closeOnExit: false), isFalse);
    });

    test('window dispose notifies hub', () {
      expect(sessionDisposeNotifiesHub(closeOnExit: true), isTrue);
    });
  });

  group('OpenSessionRegistry multi-tab', () {
    test('two different hosts remain after active switch simulation', () {
      final reg = OpenSessionRegistry();
      reg.add(const OpenSessionRef(
        id: 1,
        host: 'grog',
        port: 5901,
        shell: SessionShell.tabs,
      ));
      reg.add(const OpenSessionRef(
        id: 2,
        host: 'kgf',
        port: 5901,
        shell: SessionShell.tabs,
      ));
      // Soft dispose must NOT call removeBySessionId — tabs stay.
      expect(reg.tabSessions.length, 2);
      reg.applyTabGrabPolicy(activeId: 2);
      expect(reg.findBySessionId(1), isNotNull);
      expect(reg.findBySessionId(2), isNotNull);
      expect(reg.tabSessions.map((s) => s.id).toSet(), {1, 2});
    });
  });

  group('SessionStatusBar', () {
    testWidgets('shows Live status and opens insights on tap', (tester) async {
      final stats = SessionLinkStats();
      stats.recordFrame();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: SessionStatusBar(
              connState: SessionConnState.live,
              linkStats: stats,
              host: 'grog.example',
              port: 5901,
              scaleMode: ViewScaleMode.fit,
              grabbed: true,
              onPaste: () {},
              onScaleChanged: (_) {},
              onToggleGrab: () {},
            ),
          ),
        ),
      );
      expect(find.textContaining('Live'), findsOneWidget);
      expect(find.byKey(const Key('app-version-chip')), findsOneWidget);
      await tester.tap(find.textContaining('Live'));
      await tester.pumpAndSettle();
      expect(find.textContaining('grog.example:5901'), findsOneWidget);
      expect(find.textContaining('Update rate:'), findsOneWidget);
    });

    testWidgets('version chip shows classic line; help opens About dialog',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: aboutNavigatorKey,
          home: Scaffold(
            bottomNavigationBar: SessionStatusBar(
              connState: SessionConnState.connecting,
              linkStats: SessionLinkStats(),
              host: 'h',
              port: 5900,
              scaleMode: ViewScaleMode.fit,
              grabbed: false,
              onPaste: () {},
              onScaleChanged: (_) {},
              onToggleGrab: () {},
              coreVersion: '0.1.0',
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('app-version-chip')), findsOneWidget);
      await tester.tap(find.byKey(const Key('session-about-help')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('app-about-dialog')), findsOneWidget);
      expect(find.text(kAppProduct), findsWidgets);
      expect(find.byKey(const Key('app-about-check-updates')), findsOneWidget);
      expect(find.byKey(const Key('app-about-version')), findsOneWidget);
      expect(find.text('Licensing'), findsOneWidget);
      expect(find.text(kAppCopyright), findsOneWidget);
      expect(find.textContaining('Debug'), findsNothing);
    });

    testWidgets('shows Release input control', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: SessionStatusBar(
              connState: SessionConnState.connecting,
              linkStats: SessionLinkStats(),
              host: 'h',
              port: 5900,
              scaleMode: ViewScaleMode.fill,
              grabbed: true,
              onPaste: () {},
              onScaleChanged: (_) {},
              onToggleGrab: () {},
            ),
          ),
        ),
      );
      expect(find.text('Release input'), findsOneWidget);
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    });
  });
}
