import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/library/hub_page.dart';
import 'package:helmhost/library/library_card_widgets.dart';
import 'package:helmhost/prefs.dart';
import 'package:helmhost/session_helpers.dart';
import 'package:helmhost/storage/credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_helm_bridge.dart';

Widget _hub({
  required FakeHelmBridge bridge,
  required AppPrefs prefs,
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
        gridSize: LibraryGridSize.medium,
        onGridSizeChanged: (_) async {},
        sessionShell: SessionShell.tabs,
        onSessionShellChanged: (_) async {},
        prefs: prefs,
        bridge: bridge,
        credentials: MemoryCredentialStore(),
      ),
    ),
  );
}

Future<void> _pumpFrames(WidgetTester tester, {int n = 20}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows primary CTA and secondary CTA when no connections',
      (tester) async {
    final prefs = await AppPrefs.open();
    final bridge = FakeHelmBridge(registry: []);
    await tester.pumpWidget(_hub(bridge: bridge, prefs: prefs));
    await _pumpFrames(tester, n: 20);
    expect(find.byKey(const Key('library-empty-primary')), findsOneWidget);
    expect(find.byKey(const Key('library-empty-secondary')), findsOneWidget);
    expect(find.text('No connections yet'), findsOneWidget);
    expect(find.text('Connect a host'), findsOneWidget);
    expect(find.text('New profile…'), findsWidgets);
  });

  testWidgets('no-matches state: search that matches nothing shows Clear filters; tap restores card',
      (tester) async {
    final prefs = await AppPrefs.open();
    final bridge = FakeHelmBridge(
      registry: [
        {
          'id': 'lab:5900',
          'host': 'lab.example',
          'port': 5900,
          'display_name': 'LabBox',
        },
      ],
    );
    await tester.pumpWidget(_hub(bridge: bridge, prefs: prefs));
    await _pumpFrames(tester, n: 30);

    // Card is visible initially.
    expect(find.byType(LibraryGridCard), findsOneWidget);

    // Enter a search that matches nothing.
    final searchField = find.byType(TextField).first;
    await tester.enterText(searchField, 'zzzz-no-match');
    await tester.pumpAndSettle();

    expect(find.text('No matches'), findsOneWidget);
    expect(find.text('Clear filters'), findsOneWidget);
    expect(find.byType(LibraryGridCard), findsNothing);

    // Tap Clear filters — card reappears.
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryGridCard), findsOneWidget);
  });
}
