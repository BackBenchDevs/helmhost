import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/library/profile_editor.dart';
import 'package:helmhost/storage/credential_store.dart';

void main() {
  testWidgets('Profile editor requires domain and saves group fields',
      (tester) async {
    ProfileEditorResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showProfileEditor(
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
    await tester.enterText(find.byType(TextField).at(0), 'Lab');
    await tester.enterText(find.byType(TextField).at(1), 'lab.internal');
    // Default display is the 6th TextField (name, domain, notes, user, pwd, display).
    await tester.enterText(find.byType(TextField).at(5), '1');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.profile.name, 'Lab');
    expect(result!.profile.domain, 'lab.internal');
    expect(result!.profile.defaultDisplay, 1);
    expect(result!.profile.toJson()['default_display'], 1);
  });
}
