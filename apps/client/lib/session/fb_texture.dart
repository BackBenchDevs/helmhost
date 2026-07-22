import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Axis-aligned damage rect (matches RFB / core Rect).
class DamageRect {
  const DamageRect({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  final int x;
  final int y;
  final int w;
  final int h;

  DamageRect union(DamageRect other) {
    final x0 = x < other.x ? x : other.x;
    final y0 = y < other.y ? y : other.y;
    final x1 = (x + w) > (other.x + other.w) ? x + w : other.x + other.w;
    final y1 = (y + h) > (other.y + other.h) ? y + h : other.y + other.h;
    return DamageRect(x: x0, y: y0, w: x1 - x0, h: y1 - y0);
  }

  bool get isEmpty => w <= 0 || h <= 0;
}

/// Union [next] into [current]; returns updated damage (or [next] if current null).
DamageRect? unionDamage(DamageRect? current, DamageRect next) {
  if (next.isEmpty) return current;
  if (current == null || current.isEmpty) return next;
  return current.union(next);
}

/// macOS Flutter Texture backed by `hh_fb_copy` / `hh_fb_copy_rect`.
class FbTextureController {
  FbTextureController._(this.textureId);

  static const _channel = MethodChannel('helmhost/fb_texture');

  final int textureId;

  static bool get isSupported => !kIsWeb && Platform.isMacOS;

  static Future<FbTextureController?> create() async {
    if (!isSupported) return null;
    try {
      final id = await _channel.invokeMethod<int>('create');
      if (id == null) return null;
      return FbTextureController._(id);
    } catch (_) {
      return null;
    }
  }

  /// Copy session FB into the texture and mark frame available.
  ///
  /// When [x],[y],[w],[h] are all set, only that rect is copied (damage present).
  /// Returns `true` if a frame was presented, `false` if skipped / soft-failed.
  Future<bool> present(
    int sessionId, {
    int? x,
    int? y,
    int? w,
    int? h,
  }) async {
    try {
      final args = <String, Object?>{
        'textureId': textureId,
        'sessionId': sessionId,
      };
      if (x != null && y != null && w != null && h != null && w > 0 && h > 0) {
        args['x'] = x;
        args['y'] = y;
        args['w'] = w;
        args['h'] = h;
      }
      final r = await _channel.invokeMethod<Object?>('present', args);
      if (r == 'ok') return true;
      if (r == 'skipped') return false;
      return false;
    } on PlatformException catch (e) {
      if (e.code == 'skipped') return false;
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> dispose() async {
    try {
      await _channel.invokeMethod<void>('dispose', {'textureId': textureId});
    } catch (_) {}
  }
}
