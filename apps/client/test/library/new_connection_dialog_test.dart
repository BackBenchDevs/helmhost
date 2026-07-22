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
