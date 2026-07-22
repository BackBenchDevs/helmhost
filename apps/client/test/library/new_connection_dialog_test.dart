import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/library/connection_editor.dart';
import 'package:helmhost/session_helpers.dart';
import 'package:helmhost/storage/credential_store.dart';

void main() {
  testWidgets('New Connection OK saves without connect flag', (tester) async {
    ConnectionEditorResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showNewConnectionDialog(
                  context,
                  credentials: MemoryCredentialStore(),
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
    await tester.enterText(find.byType(TextField).first, '10.0.0.9:1');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.connect, isFalse);
    expect(result!.entry['host'], '10.0.0.9');
    expect(result!.entry['port'], 5901);
    expect(
      result!.entry['display_name'],
      displayNameFromHost('10.0.0.9'),
    );
  });

  testWidgets('New Connection Connect sets connect true', (tester) async {
    ConnectionEditorResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showNewConnectionDialog(
                  context,
                  credentials: MemoryCredentialStore(),
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
    await tester.enterText(find.byType(TextField).first, 'lab-pc');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.connect, isTrue);
    expect(result!.entry['port'], 5900);
  });

  testWidgets('Properties OK persists fields', (tester) async {
    ConnectionEditorResult? result;
    const card = LibraryCard(
      id: 'h:5900',
      host: 'h',
      port: 5900,
      displayName: 'Old',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showPropertiesDialog(
                  context,
                  existing: card,
                  credentials: MemoryCredentialStore(),
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
    // Name field is first on General tab
    await tester.enterText(find.byType(TextField).first, 'Renamed');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.connect, isFalse);
    expect(result!.entry['display_name'], 'Renamed');
  });

  testWidgets('Properties blank name derives display_name from host',
      (tester) async {
    ConnectionEditorResult? result;
    const card = LibraryCard(
      id: 'h:5900',
      host: 'h',
      port: 5900,
      displayName: 'Old',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showPropertiesDialog(
                  context,
                  existing: card,
                  credentials: MemoryCredentialStore(),
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
    await tester.enterText(find.byType(TextField).first, '');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.entry['display_name'], displayNameFromHost('h'));
  });

  test('applyProfileDefaultsToDraft maps encryption and certs', () {
    const profile = ConnectionProfileCard(
      id: 'p1',
      name: 'Lab',
      domain: 'lab.internal',
      preferVencrypt: true,
      acceptInvalidCerts: true,
      viewOnly: true,
      defaultUsername: 'ops',
      defaultDisplay: 2,
    );
    final d = applyProfileDefaultsToDraft(profile);
    expect(d['prefer_vencrypt'], isTrue);
    expect(d['accept_invalid_certs'], isTrue);
    expect(d['view_only'], isTrue);
    expect(d['username'], 'ops');
    expect(d['default_display'], 2);
  });

  testWidgets('Add to profile prefills encryption and writes profile_id',
      (tester) async {
    ConnectionEditorResult? result;
    const profile = ConnectionProfileCard(
      id: 'p-lab',
      name: 'Lab',
      domain: 'lab.internal',
      preferVencrypt: false,
      acceptInvalidCerts: true,
      defaultUsername: 'alice',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showNewConnectionDialog(
                  context,
                  credentials: MemoryCredentialStore(),
                  profiles: const [
                    ProfileChoice.named('p-lab', 'Lab', domain: 'lab.internal'),
                  ],
                  profileCards: const [profile],
                  initialProfileId: 'p-lab',
                  prefillProfile: profile,
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
    expect(find.text('Add to profile'), findsOneWidget);
    // Prefill: Accept invalid certificates checked.
    final certTile = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Accept invalid certificates'),
    );
    expect(certTile.value, isTrue);
    await tester.enterText(find.byType(TextField).first, 'box');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.entry['profile_id'], 'p-lab');
    expect(result!.entry['prefer_vencrypt'], isFalse);
    expect(result!.entry['accept_invalid_certs'], isTrue);
    expect(result!.entry['username'], 'alice');
    expect(result!.entry['host'], 'box');
    expect(result!.entry['id'], sessionKey('box.lab.internal', 5900));
  });

  testWidgets('Properties persists default Bandwidth Balanced', (tester) async {
    ConnectionEditorResult? result;
    final card = LibraryCard.fromJson({
      'id': '10.0.0.9:5901',
      'host': '10.0.0.9',
      'port': 5901,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showPropertiesDialog(
                  context,
                  existing: card,
                  credentials: MemoryCredentialStore(),
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
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(result!.entry['bandwidth_preset'], 'balanced');
  });
}
