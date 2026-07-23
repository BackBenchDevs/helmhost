import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/library/hub_page.dart';
import 'package:helmhost/library/library_card_widgets.dart';
import 'package:helmhost/library/tab_session_workspace.dart';
import 'package:helmhost/prefs.dart';
import 'package:helmhost/session/session_page.dart';
import 'package:helmhost/session_helpers.dart';
import 'package:helmhost/storage/credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_helm_bridge.dart';

Widget _hub({
  required FakeHelmBridge bridge,
  required AppPrefs prefs,
  SessionShell shell = SessionShell.tabs,
  ICredentialStore? credentials,
}) {
  return MaterialApp(
    home: SizedBox(
      width: 1280,
      height: 800,
      child: HubPage(
        themeMode: ThemeMode.system,
        onThemeModeChanged: (_) async {},
        viewMode: LibraryViewMode.grid,
        onViewModeChanged: (_) async {},
        sessionShell: shell,
        onSessionShellChanged: (_) async {},
        prefs: prefs,
        bridge: bridge,
        credentials: credentials ?? MemoryCredentialStore(),
      ),
    ),
  );
}

Future<void> _pumpFrames(WidgetTester tester, {int n = 10}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'helmhost.sessionShell': 'tabs',
    });
  });

  testWidgets('hub lists cards, connect embeds session, delete removes',
      (tester) async {
    final prefs = await AppPrefs.open();
    final bridge = FakeHelmBridge(
      registry: [
        {
          'id': 'lab:5901',
          'host': 'lab.example',
          'port': 5901,
          'display_name': 'LabBox',
        },
      ],
    );
    final creds = MemoryCredentialStore();
    await tester.pumpWidget(
      _hub(bridge: bridge, prefs: prefs, credentials: creds),
    );
    await _pumpFrames(tester, n: 30);

    expect(find.textContaining('Bridge error'), findsNothing);
    expect(find.text('LabBox'), findsWidgets);
    expect(find.byType(LibraryGridCard), findsOneWidget);

    // Connect a new host (FQDN / IP so no profile domain required).
    await tester.enterText(find.byType(TextField).first, '10.0.0.9:1');
    await tester.pump();
    await tester.tap(find.text('Connect'));
    await _pumpFrames(tester, n: 30);

    expect(bridge.upserts, isNotEmpty, reason: 'connect should upsert');
    expect(bridge.upserts.last['host'], '10.0.0.9');
    expect(bridge.grabbed, isNotEmpty);
    expect(find.byType(TabSessionWorkspace), findsOneWidget);
    expect(find.byType(SessionPage), findsWidgets);

    // Registry delete path (UI menu is under overlay after connect).
    bridge.registryRemove('lab:5901');
    expect(bridge.registry.any((e) => e['id'] == 'lab:5901'), isFalse);
  });

  testWidgets('session page embedded grabs fake session without FFI',
      (tester) async {
    final prefs = await AppPrefs.open();
    final bridge = FakeHelmBridge(width: 4, height: 4);
    final id = bridge.connect('lab', 5900);
    bridge.enqueuePoll(id, {
      'type': 'framebuffer_dirty',
      'x': 0,
      'y': 0,
      'w': 4,
      'h': 4,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SessionPage(
          sessionId: id,
          title: 'lab:5900',
          host: 'lab',
          port: 5900,
          closeOnExit: false,
          active: true,
          prefs: prefs,
          bridge: bridge,
          credentials: MemoryCredentialStore(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(bridge.grabbed, contains(id));
    expect(find.byType(SessionPage), findsOneWidget);
  });
}
