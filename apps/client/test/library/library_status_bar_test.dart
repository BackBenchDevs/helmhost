import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/library/library_status_bar.dart';
import 'package:helmhost/session_helpers.dart';

void main() {
  group('LibraryStatusBar', () {
    testWidgets('shows status text and invokes callbacks', (tester) async {
      var shell = 0;
      var view = 0;
      var theme = 0;
      var importTap = 0;
      var exportTap = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: LibraryStatusBar(
              sessionShell: SessionShell.tabs,
              viewMode: LibraryViewMode.grid,
              themeMode: ThemeMode.system,
              statusText: 'Helmhost · ok',
              onToggleShell: () => shell++,
              onToggleView: () => view++,
              onCycleTheme: () => theme++,
              onImport: () => importTap++,
              onExport: () => exportTap++,
            ),
          ),
        ),
      );

      expect(find.text('Helmhost · ok'), findsOneWidget);

      await tester.tap(find.byTooltip(
        'Session shell: Tabs (click for Windows)',
      ));
      await tester.tap(find.byTooltip('List view'));
      await tester.tap(find.byTooltip('Theme'));
      await tester.tap(find.byTooltip('Import'));
      await tester.tap(find.byTooltip('Export library'));
      await tester.pump();

      expect(shell, 1);
      expect(view, 1);
      expect(theme, 1);
      expect(importTap, 1);
      expect(exportTap, 1);
    });
  });
}
