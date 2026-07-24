import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../helpers/tap_menu.dart';

Widget _hub({
  required FakeHelmBridge bridge,
  required AppPrefs prefs,
  SessionShell shell = SessionShell.tabs,
  LibraryViewMode viewMode = LibraryViewMode.grid,
  LibraryGridSize gridSize = LibraryGridSize.medium,
  LibrarySort sort = LibrarySort.name,
  LibraryThumbRefresh thumbRefresh = LibraryThumbRefresh.normal,
  double? gridExtent,
  ValueChanged<LibraryGridSize>? onGridSizeChanged,
  ValueChanged<LibrarySort>? onSortChanged,
  ValueChanged<LibraryThumbRefresh>? onThumbRefreshChanged,
  ValueChanged<double?>? onGridExtentChanged,
  ICredentialStore? credentials,
}) {
  return MaterialApp(
    home: SizedBox(
      width: 1280,
      height: 800,
      child: HubPage(
        themeMode: ThemeMode.system,
        onThemeModeChanged: (_) async {},
        viewMode: viewMode,
        onViewModeChanged: (_) async {},
        gridSize: gridSize,
        onGridSizeChanged: (s) {
          onGridSizeChanged?.call(s);
        },
        sessionShell: shell,
        onSessionShellChanged: (_) async {},
        sort: sort,
        onSortChanged: onSortChanged,
        thumbRefresh: thumbRefresh,
        onThumbRefreshChanged: onThumbRefreshChanged,
        gridExtent: gridExtent,
        onGridExtentChanged: onGridExtentChanged,
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

    // Connect via card tap.
    await tester.tap(find.byType(LibraryGridCard));
    await _pumpFrames(tester, n: 30);

    expect(bridge.upserts, isNotEmpty, reason: 'connect should upsert');
    expect(bridge.upserts.last['host'], 'lab.example');
    expect(bridge.grabbed, isNotEmpty);
    expect(find.byType(TabSessionWorkspace), findsOneWidget);
    expect(find.byType(SessionPage), findsWidgets);

    // Registry delete path.
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

  // ── sort order ──────────────────────────────────────────────────────────────

  testWidgets('sort by lastConnected orders cards newest first', (tester) async {
    final prefs = await AppPrefs.open();
    final bridge = FakeHelmBridge(
      registry: [
        {
          'id': 'a:5900',
          'host': 'a.example',
          'port': 5900,
          'display_name': 'Alpha',
          'last_connected_at': 100,
        },
        {
          'id': 'b:5900',
          'host': 'b.example',
          'port': 5900,
          'display_name': 'Beta',
          'last_connected_at': 300,
        },
        {
          'id': 'c:5900',
          'host': 'c.example',
          'port': 5900,
          'display_name': 'Charlie',
          'last_connected_at': 200,
        },
      ],
    );
    await tester.pumpWidget(
      _hub(bridge: bridge, prefs: prefs, sort: LibrarySort.lastConnected),
    );
    await _pumpFrames(tester, n: 30);

    final cards = tester.widgetList<LibraryGridCard>(
      find.byType(LibraryGridCard),
    ).toList();
    expect(cards.length, 3);
    // Beta (300) > Charlie (200) > Alpha (100)
    expect(cards[0].card.displayName, 'Beta');
    expect(cards[1].card.displayName, 'Charlie');
    expect(cards[2].card.displayName, 'Alpha');
  });

  // ── pin reload ──────────────────────────────────────────────────────────────

  testWidgets('pin card sets favorite true in registry', (tester) async {
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

    expect(find.byType(LibraryGridCard), findsOneWidget);

    // Find the PopupMenuButton inside the LibraryGridCard.
    final menuBtn = find.descendant(
      of: find.byType(LibraryGridCard),
      matching: find.byType(PopupMenuButton<String>),
    );
    expect(menuBtn, findsOneWidget);
    await tester.tap(menuBtn, warnIfMissed: false);
    await tester.pumpAndSettle();

    // 'Pin' menu item should now appear in the overlay.
    final pinFinder = find.text('Pin');
    expect(pinFinder, findsOneWidget);
    await tester.tap(pinFinder, warnIfMissed: false);
    await tester.pumpAndSettle();

    // Bridge should have upserted with favorite=true.
    expect(
      bridge.upserts.any((u) => u['favorite'] == true),
      isTrue,
      reason: 'expected an upsert with favorite=true after Pin',
    );
  });

  // ── tag chips ───────────────────────────────────────────────────────────────

  testWidgets('tag chip filters cards; Clear chip shows all', (tester) async {
    final prefs = await AppPrefs.open();
    final bridge = FakeHelmBridge(
      registry: [
        {
          'id': 'g:5900',
          'host': 'gpu.example',
          'port': 5900,
          'display_name': 'GPU',
          'tags': ['gpu', 'lab'],
        },
        {
          'id': 'l:5900',
          'host': 'lab.example',
          'port': 5900,
          'display_name': 'Lab',
          'tags': ['lab'],
        },
      ],
    );
    await tester.pumpWidget(_hub(bridge: bridge, prefs: prefs));
    await _pumpFrames(tester, n: 30);

    expect(find.byType(LibraryGridCard), findsNWidgets(2));

    // Tap the 'gpu' FilterChip.
    await tester.tap(find.widgetWithText(FilterChip, 'gpu'));
    await tester.pumpAndSettle();

    expect(find.byType(LibraryGridCard), findsOneWidget);

    // Tap Clear.
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(find.byType(LibraryGridCard), findsNWidgets(2));
  });

  // ── shortcuts ───────────────────────────────────────────────────────────────

  testWidgets('Ctrl+2 shortcut fires onGridSizeChanged(medium)', (tester) async {
    final prefs = await AppPrefs.open();
    final bridge = FakeHelmBridge(registry: []);
    LibraryGridSize? received;
    await tester.pumpWidget(
      _hub(
        bridge: bridge,
        prefs: prefs,
        gridSize: LibraryGridSize.small,
        onGridSizeChanged: (s) => received = s,
      ),
    );
    await _pumpFrames(tester, n: 20);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(received, LibraryGridSize.medium);
  });

  testWidgets('Ctrl+Shift+S shortcut fires onSortChanged(sort.next)', (tester) async {
    final prefs = await AppPrefs.open();
    final bridge = FakeHelmBridge(registry: []);
    LibrarySort? received;
    await tester.pumpWidget(
      _hub(
        bridge: bridge,
        prefs: prefs,
        sort: LibrarySort.name,
        onSortChanged: (s) => received = s,
      ),
    );
    await _pumpFrames(tester, n: 20);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(received, LibrarySort.name.next);
  });

  // ── bulk delete ─────────────────────────────────────────────────────────────

  testWidgets('bulk delete: long-press enters selection, Select all, Delete clears registry',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final prefs = await AppPrefs.open();
    final bridge = FakeHelmBridge(
      registry: [
        {
          'id': 'a:5900',
          'host': 'a.example',
          'port': 5900,
          'display_name': 'Alpha',
        },
        {
          'id': 'b:5900',
          'host': 'b.example',
          'port': 5900,
          'display_name': 'Beta',
        },
      ],
    );
    await tester.pumpWidget(_hub(bridge: bridge, prefs: prefs));
    await _pumpFrames(tester, n: 30);

    expect(find.byType(LibraryGridCard), findsNWidgets(2));

    // Long-press to enter selection mode.
    await tester.longPress(find.byType(LibraryGridCard).first);
    await tester.pumpAndSettle();

    // Selection bar should be visible; tap Select all.
    expect(find.text('Select all'), findsOneWidget);
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();

    // Tap Delete in the selection bar.
    // There may be multiple 'Delete' texts — the one in the selection bar.
    await tester.tap(find.text('Delete').first);
    await tester.pumpAndSettle();

    // Confirmation dialog appears; tap the FilledButton 'Delete'.
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Delete').last, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(bridge.registry, isEmpty);
  });
}
