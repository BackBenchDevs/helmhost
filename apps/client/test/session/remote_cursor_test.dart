import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/session/remote_cursor.dart';
import 'package:helmhost/session/session_shortcuts.dart';
import 'package:flutter/services.dart';

void main() {
  group('RemoteCursorShape.fromPollEvent', () {
    test('parses rgba_b64 shape', () {
      final rgba = List<int>.generate(16, (i) => i); // 2x2
      final ev = {
        'type': 'cursor_changed',
        'w': 2,
        'h': 2,
        'hotspot_x': 1,
        'hotspot_y': 0,
        'rgba_b64': base64Encode(rgba),
      };
      final shape = RemoteCursorShape.fromPollEvent(ev)!;
      expect(shape.width, 2);
      expect(shape.height, 2);
      expect(shape.hotspotX, 1);
      expect(shape.isEmpty, isFalse);
      expect(shape.rgba.length, 16);
    });

    test('empty shape hides cursor', () {
      final shape = RemoteCursorShape.fromPollEvent({
        'type': 'cursor_changed',
        'w': 0,
        'h': 0,
        'hotspot_x': 0,
        'hotspot_y': 0,
        'rgba_b64': '',
      })!;
      expect(shape.isEmpty, isTrue);
    });
  });

  group('sessionMouseCursor policy', () {
    test('exclusiveGrab Meta+V still pasteToRemote', () {
      expect(
        classifySessionLocalShortcut(
          key: LogicalKeyboardKey.keyV,
          shift: false,
          control: false,
          meta: true,
          exclusiveGrab: true,
        ),
        SessionLocalShortcut.pasteToRemote,
      );
    });
  });
}
