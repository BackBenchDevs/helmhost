import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/keysyms.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('charToKeysym', () {
    test('ascii printable', () {
      expect(charToKeysym('a'), 0x0061);
      expect(charToKeysym('A'), 0x0041);
      expect(charToKeysym(' '), 0x0020);
      expect(charToKeysym('~'), 0x007e);
    });

    test('latin1 and unicode plane', () {
      expect(charToKeysym('\u{00E9}'), 0x00e9);
      expect(charToKeysym('\u{4E2D}'), 0x01004e2d);
    });

    test('empty is zero', () {
      expect(charToKeysym(''), 0);
    });
  });

  group('logicalKeyToKeysym', () {
    test('modifiers L/R — Cmd is Super, not Control', () {
      expect(logicalKeyToKeysym(LogicalKeyboardKey.controlLeft), xkControlL);
      expect(logicalKeyToKeysym(LogicalKeyboardKey.controlRight), xkControlR);
      expect(logicalKeyToKeysym(LogicalKeyboardKey.shiftLeft), 0xffe1);
      expect(logicalKeyToKeysym(LogicalKeyboardKey.shiftRight), 0xffe2);
      expect(logicalKeyToKeysym(LogicalKeyboardKey.altLeft), 0xffe9);
      expect(logicalKeyToKeysym(LogicalKeyboardKey.altRight), 0xffea);
      expect(logicalKeyToKeysym(LogicalKeyboardKey.metaLeft), 0xffeb);
      expect(logicalKeyToKeysym(LogicalKeyboardKey.metaRight), 0xffec);
    });

    test('navigation and editing', () {
      expect(logicalKeyToKeysym(LogicalKeyboardKey.arrowLeft), 0xff51);
      expect(logicalKeyToKeysym(LogicalKeyboardKey.arrowUp), 0xff52);
      expect(logicalKeyToKeysym(LogicalKeyboardKey.arrowRight), 0xff53);
      expect(logicalKeyToKeysym(LogicalKeyboardKey.arrowDown), 0xff54);
      expect(logicalKeyToKeysym(LogicalKeyboardKey.enter), 0xff0d);
      expect(logicalKeyToKeysym(LogicalKeyboardKey.escape), 0xff1b);
      expect(logicalKeyToKeysym(LogicalKeyboardKey.tab), 0xff09);
      expect(logicalKeyToKeysym(LogicalKeyboardKey.backspace), 0xff08);
      expect(logicalKeyToKeysym(LogicalKeyboardKey.delete), 0xffff);
      expect(logicalKeyToKeysym(LogicalKeyboardKey.home), 0xff50);
      expect(logicalKeyToKeysym(LogicalKeyboardKey.end), 0xff57);
    });

    test('function keys sample', () {
      expect(logicalKeyToKeysym(LogicalKeyboardKey.f1), 0xffbe);
      expect(logicalKeyToKeysym(LogicalKeyboardKey.f12), 0xffc9);
    });

    test('letters and digits fallback', () {
      expect(logicalKeyToKeysym(LogicalKeyboardKey.keyA), 0x0061);
      expect(logicalKeyToKeysym(LogicalKeyboardKey.keyC), 0x0063);
      expect(logicalKeyToKeysym(LogicalKeyboardKey.digit0), 0x0030);
      expect(logicalKeyToKeysym(LogicalKeyboardKey.digit9), 0x0039);
    });

    test('unmapped returns null', () {
      expect(logicalKeyToKeysym(LogicalKeyboardKey.fn), isNull);
    });
  });

  group('keysymForKeyEvent', () {
    test('uses character for shifted letter', () {
      final ev = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyA,
        logicalKey: LogicalKeyboardKey.keyA,
        character: 'A',
        timeStamp: Duration.zero,
      );
      expect(keysymForKeyEvent(ev), 0x0041);
    });

    test('control left from logical table', () {
      final ev = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.controlLeft,
        logicalKey: LogicalKeyboardKey.controlLeft,
        timeStamp: Duration.zero,
      );
      expect(keysymForKeyEvent(ev), xkControlL);
    });

    test('meta left is Super', () {
      final ev = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.metaLeft,
        logicalKey: LogicalKeyboardKey.metaLeft,
        timeStamp: Duration.zero,
      );
      expect(keysymForKeyEvent(ev), 0xffeb);
    });

    test('escape prefers table over character', () {
      final ev = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.escape,
        logicalKey: LogicalKeyboardKey.escape,
        character: '\x1b',
        timeStamp: Duration.zero,
      );
      expect(keysymForKeyEvent(ev), 0xff1b);
    });

    test('lowercase a without character uses logical', () {
      final ev = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyA,
        logicalKey: LogicalKeyboardKey.keyA,
        timeStamp: Duration.zero,
      );
      expect(keysymForKeyEvent(ev), 0x0061);
    });
  });
}
