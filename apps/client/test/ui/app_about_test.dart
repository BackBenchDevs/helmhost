import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/gen/app_version.dart';
import 'package:helmhost/ui/app_about.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('classic status line unchanged', () {
    expect(appVersionStatusLine(), kAppStatusLine);
  });

  test('full plain text still has identity dump for diagnostics', () {
    final t = buildAboutReport(coreVersion: '1.2.3').toPlainText();
    expect(t, contains(kAppCopyright));
    expect(t, contains('Product:'));
    expect(t, contains('— Version —'));
    expect(t, contains(kAppCodename));
  });

  testWidgets('About dialog shows Firefox-style layout; no debug',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: aboutNavigatorKey,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppAbout(
                context: context,
                coreVersion: '1.2.3',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app-about-dialog')), findsOneWidget);
    expect(find.byKey(const Key('app-about-product')), findsOneWidget);
    expect(find.text(kAppProduct), findsWidgets);
    expect(find.text(kAppCodename), findsOneWidget);
    expect(find.byKey(const Key('app-about-check-updates')), findsOneWidget);
    expect(find.text('Check for updates'), findsOneWidget);
    expect(
      find.text('${aboutUiVersionLabel()} · Core v1.2.3'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('app-about-website')), findsOneWidget);
    expect(find.text(kAppAboutBlurb), findsOneWidget);
    expect(find.text('Licensing'), findsOneWidget);
    expect(find.byKey(const Key('app-about-licenses')), findsOneWidget);
    expect(find.text(kAppCopyright), findsOneWidget);
    expect(find.text(kAppLicenseShort), findsNothing);
    expect(find.textContaining('Debug'), findsNothing);
    expect(find.textContaining('channel not ready'), findsNothing);
    expect(find.textContaining('Bundle ID'), findsNothing);
    expect(find.textContaining('GPL'), findsNothing);

    await tester.tap(find.byKey(const Key('app-about-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app-about-dialog')), findsNothing);
  });

  testWidgets('Licensing opens product license and third-party notices',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: aboutNavigatorKey,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppAbout(context: context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app-about-licenses')), findsOneWidget);
    await tester.tap(find.byKey(const Key('app-about-licenses')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app-licenses-dialog')), findsOneWidget);
    expect(find.byKey(const Key('app-licenses-title')), findsOneWidget);
    expect(find.text(kAppLicenseShort), findsWidgets);
    expect(find.text(kAppCopyright), findsWidgets);
    expect(find.byKey(const Key('app-licenses-product-text')), findsOneWidget);
    expect(
      find.textContaining('BackBenchDevs Proprietary Software License'),
      findsOneWidget,
    );

    await tester.tap(find.text('Third-party'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('app-licenses-third-party-text')),
      findsOneWidget,
    );
    expect(find.textContaining('Third-party notices'), findsOneWidget);
  });
}
