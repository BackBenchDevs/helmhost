import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/input/exclusive_grab.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    ExclusiveGrab.debugResetModalPause();
  });

  group('isExclusiveReleaseKey', () {
    test('platform release chord', () {
      if (Platform.isMacOS) {
        expect(isExclusiveReleaseKey(LogicalKeyboardKey.metaRight), isTrue);
        expect(isExclusiveReleaseKey(LogicalKeyboardKey.controlRight), isFalse);
      } else {
        expect(isExclusiveReleaseKey(LogicalKeyboardKey.controlRight), isTrue);
        expect(isExclusiveReleaseKey(LogicalKeyboardKey.metaRight), isFalse);
      }
      expect(isExclusiveReleaseKey(LogicalKeyboardKey.controlLeft), isFalse);
      expect(isExclusiveReleaseKey(LogicalKeyboardKey.metaLeft), isFalse);
    });
  });

  group('ExclusiveGrab channel', () {
    test('key payload includes physical; localShortcut paste', () async {
      final channel = const MethodChannel('helmhost/exclusive_grab');
      final log = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        log.add(call);
        return null;
      });

      final grab = ExclusiveGrab(channel: channel, forceSupported: true);
      final keys = <(int, bool, int)>[];
      final shortcuts = <String>[];
      await grab.start(
        onKey: (ks, down, phys) => keys.add((ks, down, phys)),
        onReleaseChord: () {},
        onLocalShortcut: shortcuts.add,
      );

      // Simulate native → Dart.
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'helmhost/exclusive_grab',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('key', {
            'keysym': 0x41,
            'down': true,
            'physical': 0,
          }),
        ),
        (_) {},
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'helmhost/exclusive_grab',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('localShortcut', {'kind': 'paste'}),
        ),
        (_) {},
      );

      expect(keys, [(0x41, true, 0)]);
      expect(shortcuts, ['paste']);
      await grab.stop();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('pauseForModal stops tap; resume restarts when wantActive', () async {
      final channel = const MethodChannel('helmhost/exclusive_grab');
      final log = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        log.add(call);
        return null;
      });

      final grab = ExclusiveGrab(channel: channel, forceSupported: true);
      await grab.start(
        onKey: (_, __, ___) {},
        onReleaseChord: () {},
      );
      expect(grab.isActive, isTrue);
      expect(log.where((c) => c.method == 'start'), hasLength(1));

      await ExclusiveGrab.pauseForModal();
      expect(ExclusiveGrab.debugUiPauseDepth, 1);
      expect(grab.isActive, isFalse);
      expect(grab.wantsActive, isTrue);
      expect(log.where((c) => c.method == 'stop'), hasLength(1));

      // Nested pause
      await ExclusiveGrab.pauseForModal();
      expect(ExclusiveGrab.debugUiPauseDepth, 2);
      expect(log.where((c) => c.method == 'stop'), hasLength(1));

      await ExclusiveGrab.resumeAfterModal();
      expect(ExclusiveGrab.debugUiPauseDepth, 1);
      expect(grab.isActive, isFalse);
      expect(log.where((c) => c.method == 'start'), hasLength(1));

      await ExclusiveGrab.resumeAfterModal();
      expect(ExclusiveGrab.debugUiPauseDepth, 0);
      expect(grab.isActive, isTrue);
      expect(log.where((c) => c.method == 'start'), hasLength(2));

      await grab.stop();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('start while paused defers tap until resume', () async {
      final channel = const MethodChannel('helmhost/exclusive_grab');
      final log = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        log.add(call);
        return null;
      });

      await ExclusiveGrab.pauseForModal();
      final grab = ExclusiveGrab(channel: channel, forceSupported: true);
      await grab.start(
        onKey: (_, __, ___) {},
        onReleaseChord: () {},
      );
      expect(grab.isActive, isFalse);
      expect(grab.wantsActive, isTrue);
      expect(log.where((c) => c.method == 'start'), isEmpty);

      await ExclusiveGrab.resumeAfterModal();
      expect(grab.isActive, isTrue);
      expect(log.where((c) => c.method == 'start'), hasLength(1));

      await grab.stop();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
  });
}
