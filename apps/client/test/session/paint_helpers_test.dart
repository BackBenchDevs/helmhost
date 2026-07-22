import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/session/paint_helpers.dart';

void main() {
  group('unionDamage', () {
    test('null current returns next', () {
      const next = DamageRect(x: 1, y: 2, w: 3, h: 4);
      expect(unionDamage(null, next), same(next));
    });

    test('unions overlapping rects', () {
      const a = DamageRect(x: 0, y: 0, w: 10, h: 10);
      const b = DamageRect(x: 5, y: 5, w: 10, h: 10);
      final u = unionDamage(a, b)!;
      expect(u.x, 0);
      expect(u.y, 0);
      expect(u.w, 15);
      expect(u.h, 15);
    });

    test('empty next leaves current', () {
      const a = DamageRect(x: 1, y: 1, w: 2, h: 2);
      expect(unionDamage(a, const DamageRect(x: 0, y: 0, w: 0, h: 0)), a);
    });
  });

  group('shouldFlushPointerImmediate', () {
    test('move with same buttons is not immediate', () {
      expect(
        shouldFlushPointerImmediate(buttons: 0, lastButtons: 0),
        isFalse,
      );
    });

    test('button down/up is always immediate', () {
      expect(
        shouldFlushPointerImmediate(buttons: 1, lastButtons: 0),
        isTrue,
      );
      expect(
        shouldFlushPointerImmediate(buttons: 0, lastButtons: 1),
        isTrue,
      );
    });
  });

  group('shouldFallbackToDartDecode', () {
    test('presentOk never falls back', () {
      expect(
        shouldFallbackToDartDecode(
          embedded: true,
          hadTextureSuccess: false,
          presentOk: true,
          failStreak: 99,
        ),
        isFalse,
      );
    });

    test('embedded after texture success never falls back', () {
      expect(
        shouldFallbackToDartDecode(
          embedded: true,
          hadTextureSuccess: true,
          presentOk: false,
          failStreak: 99,
        ),
        isFalse,
      );
    });

    test('soft-skip below fail limit', () {
      expect(
        shouldFallbackToDartDecode(
          embedded: false,
          hadTextureSuccess: true,
          presentOk: false,
          failStreak: 2,
        ),
        isFalse,
      );
    });

    test('fallback after fail streak without embed lock', () {
      expect(
        shouldFallbackToDartDecode(
          embedded: false,
          hadTextureSuccess: true,
          presentOk: false,
          failStreak: 3,
        ),
        isTrue,
      );
    });

    test('fallback when never had texture success', () {
      expect(
        shouldFallbackToDartDecode(
          embedded: false,
          hadTextureSuccess: false,
          presentOk: false,
          failStreak: 1,
        ),
        isTrue,
      );
    });
  });
}
