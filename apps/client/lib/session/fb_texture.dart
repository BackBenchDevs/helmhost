import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// macOS Flutter Texture backed by `hh_fb_copy` in native code (no Dart pixel hop).
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
  /// Returns `true` if a frame was presented, `false` if skipped (no FB yet)
  /// or soft-failed (caller should fall back to Dart paint).
  Future<bool> present(int sessionId) async {
    try {
      final r = await _channel.invokeMethod<Object?>('present', {
        'textureId': textureId,
        'sessionId': sessionId,
      });
      if (r == 'ok') return true;
      if (r == 'skipped') return false;
      return false;
    } on PlatformException catch (e) {
      // no_ffi / present_failed → Dart RawImage fallback
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
