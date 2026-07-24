import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/gen/app_version.dart';
import 'package:helmhost/library/library_status_bar.dart';
import 'package:helmhost/session_helpers.dart';
import 'package:helmhost/ui/app_about.dart';

import '../helpers/tap_menu.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('about helpers', () {
    test('status line keeps classic product format', () {
      expect(appVersionStatusLine(), kAppStatusLine);
    });

    test('AboutReport includes version identity and debug', () {
      final r = buildAboutReport(coreVersion: '0.1.0');
      final text = r.toPlainText();
      expect(text, contains(kAppProduct));
      expect(text, contains(kAppCodename));
      expect(text, contains(kAppVersion));
      expect(text, contains(kAppBuild));
      expect(text, contains(kAppChannel));
      expect(text, contains(aboutUiVersionLabel()));
      expect(text, contains('Core (Rust FFI): v0.1.0'));
      expect(text, contains(kAppBundleId));
      expect(text, contains(kAppCopyright));
      expect(text, contains('— Debug —'));
      expect(text, contains('Build mode:'));
      expect(text, contains('OS:'));
    });
  });

  group('LibraryStatusBar', () {
    Widget _buildBar({
      LibraryViewMode viewMode = LibraryViewMode.grid,
      LibraryGridSize gridSize = LibraryGridSize.medium,
      LibrarySort sort = LibrarySort.name,
      LibraryThumbRefresh thumbRefresh = LibraryThumbRefresh.normal,
      double? gridExtent,
      int? connectionCount,
      int? connectionTotal,
      ValueChanged<LibraryGridSize>? onGridSizeChanged,
      ValueChanged<LibrarySort>? onSortChanged,
      ValueChanged<LibraryThumbRefresh>? onThumbRefreshChanged,
      ValueChanged<double?>? onGridExtentChanged,
    }) {
      return MaterialApp(
        navigatorKey: aboutNavigatorKey,
        home: Scaffold(
          bottomNavigationBar: LibraryStatusBar(
            sessionShell: SessionShell.tabs,
            viewMode: viewMode,
            gridSize: gridSize,
            themeMode: ThemeMode.system,
            coreVersion: '0.1.0',
            sort: sort,
            onSortChanged: onSortChanged ?? (_) {},
            thumbRefresh: thumbRefresh,
            onThumbRefreshChanged: onThumbRefreshChanged ?? (_) {},
            onToggleShell: () {},
            onToggleView: () {},
            onGridSizeChanged: onGridSizeChanged ?? (_) {},
            onCycleTheme: () {},
            onImport: () {},
            onExport: () {},
            gridExtent: gridExtent,
            onGridExtentChanged: onGridExtentChanged,
            connectionCount: connectionCount,
            connectionTotal: connectionTotal,
          ),
        ),
      );
    }

    testWidgets('help opens custom About dialog without debug', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: aboutNavigatorKey,
          home: Scaffold(
            bottomNavigationBar: LibraryStatusBar(
              sessionShell: SessionShell.tabs,
              viewMode: LibraryViewMode.grid,
              gridSize: LibraryGridSize.medium,
              themeMode: ThemeMode.system,
              coreVersion: '0.1.0',
              onToggleShell: () {},
              onToggleView: () {},
              onGridSizeChanged: (_) {},
              onCycleTheme: () {},
              onImport: () {},
              onExport: () {},
            ),
          ),
        ),
      );

      expect(find.text(kAppStatusLine), findsOneWidget);
      await tester.tap(find.byKey(const Key('library-about-help')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('app-about-dialog')), findsOneWidget);
      expect(find.text(kAppProduct), findsWidgets);
      expect(find.byKey(const Key('app-about-check-updates')), findsOneWidget);
      expect(find.byKey(const Key('app-about-version')), findsOneWidget);
      expect(find.text('Licensing'), findsOneWidget);
      expect(find.text(kAppCopyright), findsOneWidget);
      expect(find.textContaining('Debug'), findsNothing);
      expect(find.textContaining('channel not ready'), findsNothing);
    });

    testWidgets('grid-size popup shows in grid mode', (tester) async {
      LibraryGridSize? received;
      await tester.pumpWidget(
        _buildBar(onGridSizeChanged: (s) => received = s),
      );
      expect(find.byKey(const Key('library-grid-size')), findsOneWidget);
      await tester.tap(find.byKey(const Key('library-grid-size')));
      await tester.pumpAndSettle();
      await tapMenuItem(tester, 'Large');
      expect(received, LibraryGridSize.large);
    });

    testWidgets('grid-size control hidden in list mode', (tester) async {
      await tester.pumpWidget(_buildBar(viewMode: LibraryViewMode.list));
      expect(find.byKey(const Key('library-grid-size')), findsNothing);
    });

    testWidgets('sort popup selects sort value', (tester) async {
      LibrarySort? received;
      await tester.pumpWidget(
        _buildBar(onSortChanged: (s) => received = s),
      );
      await tester.tap(find.byKey(const Key('library-sort')));
      await tester.pumpAndSettle();
      await tapMenuItem(tester, 'Last connected');
      expect(received, LibrarySort.lastConnected);
    });

    // ── tooltip ──────────────────────────────────────────────────────────────

    testWidgets('grid-size button has tooltip Grid size: Medium', (tester) async {
      await tester.pumpWidget(_buildBar(gridSize: LibraryGridSize.medium));
      expect(find.byTooltip('Grid size: Medium'), findsOneWidget);
    });

    // ── connection count ─────────────────────────────────────────────────────

    testWidgets('connectionCount + connectionTotal shows N of M', (tester) async {
      await tester.pumpWidget(
        _buildBar(connectionCount: 3, connectionTotal: 10),
      );
      expect(find.textContaining('3 of 10'), findsOneWidget);
    });

    testWidgets('connectionCount only shows N connections', (tester) async {
      await tester.pumpWidget(
        _buildBar(connectionCount: 3),
      );
      expect(find.textContaining('3 connections'), findsOneWidget);
    });

    // ── thumb-refresh menu ───────────────────────────────────────────────────

    testWidgets('thumb menu Slow fires LibraryThumbRefresh.slow', (tester) async {
      LibraryThumbRefresh? received;
      await tester.pumpWidget(
        _buildBar(onThumbRefreshChanged: (r) => received = r),
      );
      await tester.tap(find.byKey(const Key('library-thumb-refresh')));
      await tester.pumpAndSettle();
      await tapMenuItem(tester, 'Slow (5 s)');
      expect(received, LibraryThumbRefresh.slow);
    });

    // ── custom extent dialog ─────────────────────────────────────────────────

    testWidgets('Custom… dialog has Slider and Apply sets value', (tester) async {
      double? extentSet;
      await tester.pumpWidget(
        _buildBar(
          onGridExtentChanged: (v) => extentSet = v,
          onGridSizeChanged: (_) {},
        ),
      );
      await tester.tap(find.byKey(const Key('library-grid-size')));
      await tester.pumpAndSettle();
      await tapMenuItem(tester, 'Custom…');
      // Dialog is open; Slider is present.
      expect(find.byType(Slider), findsOneWidget);
      // Tap Apply.
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      // extentSet should have been called (value = whatever the slider was at).
      expect(extentSet, isNotNull);
    });

    testWidgets('Custom… Reset to preset calls onGridExtentChanged(null)', (tester) async {
      double? extentSet = 300;
      await tester.pumpWidget(
        _buildBar(
          gridExtent: 300,
          onGridExtentChanged: (v) => extentSet = v,
          onGridSizeChanged: (_) {},
        ),
      );
      await tester.tap(find.byKey(const Key('library-grid-size')));
      await tester.pumpAndSettle();
      // When gridExtent != null the item reads "Custom (300 px)…"
      final customFinder = find.textContaining('Custom');
      await tester.ensureVisible(customFinder.last);
      await tester.pumpAndSettle();
      await tester.tap(customFinder.last, warnIfMissed: false);
      await tester.pumpAndSettle();
      // Reset to preset button.
      await tester.tap(find.text('Reset to preset'));
      await tester.pumpAndSettle();
      expect(extentSet, isNull);
    });
  });
}
