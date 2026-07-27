import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/input/exclusive_grab.dart';

void main() {
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
}
