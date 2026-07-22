import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/session/session_shortcuts.dart';

void main() {
  group('classifySessionLocalShortcut', () {
    test('Meta+V is paste', () {
      expect(
        classifySessionLocalShortcut(
          key: LogicalKeyboardKey.keyV,
          shift: false,
          control: false,
          meta: true,
        ),
        SessionLocalShortcut.pasteToRemote,
      );
    });

    test('Shift+Insert is paste', () {
      expect(
        classifySessionLocalShortcut(
          key: LogicalKeyboardKey.insert,
          shift: true,
          control: false,
          meta: false,
        ),
        SessionLocalShortcut.pasteToRemote,
      );
    });

    test('Control+V is forwarded (not local paste)', () {
      expect(
        classifySessionLocalShortcut(
          key: LogicalKeyboardKey.keyV,
          shift: false,
          control: true,
          meta: false,
        ),
        isNull,
      );
    });

    test('Meta+C is consume (not interrupt)', () {
      expect(
        classifySessionLocalShortcut(
          key: LogicalKeyboardKey.keyC,
          shift: false,
          control: false,
          meta: true,
        ),
        SessionLocalShortcut.consume,
      );
    });

    test('Meta+Shift+C is consume', () {
      expect(
        classifySessionLocalShortcut(
          key: LogicalKeyboardKey.keyC,
          shift: true,
          control: false,
          meta: true,
        ),
        SessionLocalShortcut.consume,
      );
    });

    test('Control+C is forwarded (remote interrupt)', () {
      expect(
        classifySessionLocalShortcut(
          key: LogicalKeyboardKey.keyC,
          shift: false,
          control: true,
          meta: false,
        ),
        isNull,
      );
    });

    test('Control+Shift+C is forwarded (remote terminal copy)', () {
      expect(
        classifySessionLocalShortcut(
          key: LogicalKeyboardKey.keyC,
          shift: true,
          control: true,
          meta: false,
        ),
        isNull,
      );
    });

    test('plain C is forwarded', () {
      expect(
        classifySessionLocalShortcut(
          key: LogicalKeyboardKey.keyC,
          shift: false,
          control: false,
          meta: false,
        ),
        isNull,
      );
    });
  });

  group('isPasteToRemoteShortcut', () {
    test('Meta+V only', () {
      expect(
        isPasteToRemoteShortcut(
          key: LogicalKeyboardKey.keyV,
          shift: false,
          control: false,
          meta: true,
        ),
        isTrue,
      );
      expect(
        isPasteToRemoteShortcut(
          key: LogicalKeyboardKey.keyV,
          shift: false,
          control: true,
          meta: false,
        ),
        isFalse,
      );
    });
  });
}
