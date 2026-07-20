import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost_client/library/auth_dialog.dart';
import 'package:helmhost_client/main.dart';
import 'package:helmhost_client/prefs.dart';
import 'package:helmhost_client/session_helpers.dart';
import 'package:helmhost_client/storage/credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Library shows title, regex search, empty grid', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await AppPrefs.open();
    await tester.pumpWidget(HubApp(prefs: prefs));
    await tester.pump();
    expect(find.text('Library'), findsOneWidget);
    expect(find.textContaining('No saved connections yet'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('Hub pumps with dark theme', (tester) async {
    SharedPreferences.setMockInitialValues({'helmhost.themeMode': 'dark'});
    final prefs = await AppPrefs.open();
    await tester.pumpWidget(HubApp(prefs: prefs));
    await tester.pump();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });

  testWidgets('List view mode toggle', (tester) async {
    SharedPreferences.setMockInitialValues({'helmhost.libraryViewMode': 'list'});
    final prefs = await AppPrefs.open();
    await tester.pumpWidget(HubApp(prefs: prefs));
    await tester.pump();
    expect(find.byIcon(Icons.view_list), findsNothing);
    expect(find.byIcon(Icons.grid_view), findsOneWidget);
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
    expect(find.text('Sign in'), findsOneWidget);
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
