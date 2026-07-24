import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/library/auth_dialog.dart';
import 'package:helmhost/library/library_status_bar.dart';
import 'package:helmhost/main.dart';
import 'package:helmhost/prefs.dart';
import 'package:helmhost/session_helpers.dart';
import 'package:helmhost/storage/credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Library shows address bar and empty state', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await AppPrefs.open();
    await tester.pumpWidget(HubApp(prefs: prefs));
    await tester.pump();
    expect(find.text('Connect'), findsOneWidget);
    expect(find.textContaining('No connections yet'), findsOneWidget);
    // 'New profile…' appears in sidebar + empty-state CTA.
    expect(find.text('New profile…'), findsWidgets);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('Hub pumps with dark theme', (tester) async {
    SharedPreferences.setMockInitialValues({'helmhost.themeMode': 'dark'});
    final prefs = await AppPrefs.open();
    await tester.pumpWidget(HubApp(prefs: prefs));
    await tester.pump();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });

  testWidgets('Library chrome controls live in status bar not AppBar',
      (tester) async {
    SharedPreferences.setMockInitialValues({'helmhost.libraryViewMode': 'list'});
    final prefs = await AppPrefs.open();
    await tester.pumpWidget(HubApp(prefs: prefs));
    await tester.pump();
    // Grid toggle icon is in LibraryStatusBar (list mode → show grid icon).
    expect(find.byIcon(Icons.grid_view), findsOneWidget);
    expect(find.byTooltip('Theme'), findsOneWidget);
    expect(find.byTooltip('Import'), findsOneWidget);
    expect(find.byTooltip('Export library'), findsOneWidget);
    expect(find.byType(LibraryStatusBar), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets('AuthDialog shows username when needed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAuthDialog(
                context,
                need: AuthNeed.usernamePassword,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Authentication'), findsOneWidget);
    expect(find.text('Remember on this device'), findsOneWidget);
  });

  testWidgets('AuthDialog savePermanently checkbox', (tester) async {
    AuthDialogResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showAuthDialog(
                  context,
                  need: AuthNeed.password,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'secret');
    await tester.tap(find.text('Remember on this device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(result?.password, 'secret');
    expect(result?.savePermanently, isTrue);
  });

  test('MemoryCredentialStore round-trip', () async {
    final store = MemoryCredentialStore();
    await store.writePassword('host:5900', 'secret');
    expect(await store.readPassword('host:5900'), 'secret');
    await store.deletePassword('host:5900');
    expect(await store.readPassword('host:5900'), isNull);
  });

  test('FileCredentialStore round-trip', () async {
    final dir = await Directory.systemTemp.createTemp('helmhost_creds_');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileCredentialStore(root: dir);
    await store.writePassword('host:5900', 'secret');
    expect(await store.readPassword('host:5900'), 'secret');
    final reopened = FileCredentialStore(root: dir);
    expect(await reopened.readPassword('host:5900'), 'secret');
    await reopened.deletePassword('host:5900');
    expect(await reopened.readPassword('host:5900'), isNull);
  });
}
