import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/prefs.dart';
import 'package:helmhost/session/session_page.dart';
import 'package:helmhost/storage/credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_helm_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Fit mode still requests desktop size on view layout',
      (tester) async {
    SharedPreferences.setMockInitialValues({'helmhost.viewScaleMode': 'fit'});
    final prefs = await AppPrefs.open();
    final bridge = FakeHelmBridge(width: 64, height: 48);
    final id = bridge.connect('lab', 5900);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: SessionPage(
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
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(bridge.desktopSizes, isNotEmpty);
    final last = bridge.desktopSizes.last;
    expect(last.$1, id);
    expect(last.$2, greaterThan(64));
    expect(last.$3, greaterThan(48));
  });

  testWidgets('suppressRemoteResize skips requestDesktopSize', (tester) async {
    SharedPreferences.setMockInitialValues({'helmhost.viewScaleMode': 'fit'});
    final prefs = await AppPrefs.open();
    final bridge = FakeHelmBridge(width: 64, height: 48);
    final id = bridge.connect('lab', 5900);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: SessionPage(
            sessionId: id,
            title: 'lab:5900',
            host: 'lab',
            port: 5900,
            closeOnExit: false,
            active: true,
            suppressRemoteResize: true,
            prefs: prefs,
            bridge: bridge,
            credentials: MemoryCredentialStore(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(bridge.desktopSizes, isEmpty);
  });

  testWidgets('clearing suppress schedules resize after settle', (tester) async {
    SharedPreferences.setMockInitialValues({'helmhost.viewScaleMode': 'fit'});
    final prefs = await AppPrefs.open();
    final bridge = FakeHelmBridge(width: 64, height: 48);
    final id = bridge.connect('lab', 5900);

    Widget build({required bool suppress}) {
      return MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: SessionPage(
            sessionId: id,
            title: 'lab:5900',
            host: 'lab',
            port: 5900,
            closeOnExit: false,
            active: true,
            suppressRemoteResize: suppress,
            prefs: prefs,
            bridge: bridge,
            credentials: MemoryCredentialStore(),
          ),
        ),
      );
    }

    await tester.pumpWidget(build(suppress: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(bridge.desktopSizes, isEmpty);

    await tester.pumpWidget(build(suppress: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(bridge.desktopSizes, isNotEmpty);
  });
}
