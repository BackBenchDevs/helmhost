import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/session/session_link_stats.dart';
import 'package:helmhost/session/session_status_bar.dart';
import 'package:helmhost/session_helpers.dart';

void main() {
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
      await tester.tap(find.textContaining('Live'));
      await tester.pumpAndSettle();
      expect(find.textContaining('grog.example:5901'), findsOneWidget);
      expect(find.textContaining('Update rate:'), findsOneWidget);
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
