import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/gen/app_version.dart';
import 'package:helmhost/library/library_status_bar.dart';
import 'package:helmhost/session_helpers.dart';
import 'package:helmhost/ui/app_about.dart';

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
    testWidgets('help opens custom About dialog without debug', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: aboutNavigatorKey,
          home: Scaffold(
            bottomNavigationBar: LibraryStatusBar(
              sessionShell: SessionShell.tabs,
              viewMode: LibraryViewMode.grid,
              themeMode: ThemeMode.system,
              coreVersion: '0.1.0',
              onToggleShell: () {},
              onToggleView: () {},
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
  });
}
