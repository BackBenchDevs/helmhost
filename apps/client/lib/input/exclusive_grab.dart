import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channelName = 'helmhost/exclusive_grab';

/// Native exclusive keyboard grab (Alt+Tab etc. → RFB while active).
///
/// Supported: macOS (CGEventTap), Windows (WH_KEYBOARD_LL).
/// Linux: no-op for now (Wayland cannot fully grab).
///
/// Channel payload for keys: `{ keysym, down, physical }` (TigerVNC press/release
/// by physical id). Local viewer chords: `localShortcut` with `kind: paste|consume`.
class ExclusiveGrab {
  ExclusiveGrab({
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel(_channelName);

  final MethodChannel _channel;
  var _active = false;
  void Function(int keysym, bool down, int physical)? _onKey;
  VoidCallback? _onReleaseChord;
  void Function(String kind)? _onLocalShortcut;

  bool get isSupported =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows);

  bool get isActive => _active;

  /// Start swallowing host shortcuts and forwarding keysyms.
  Future<void> start({
    required void Function(int keysym, bool down, int physical) onKey,
    required VoidCallback onReleaseChord,
    void Function(String kind)? onLocalShortcut,
  }) async {
    if (!isSupported) return;
    _onKey = onKey;
    _onReleaseChord = onReleaseChord;
    _onLocalShortcut = onLocalShortcut;
    _channel.setMethodCallHandler(_onPlatformCall);
    try {
      await _channel.invokeMethod<void>('start');
      _active = true;
    } on MissingPluginException {
      _active = false;
      _channel.setMethodCallHandler(null);
    } catch (_) {
      _active = false;
      _channel.setMethodCallHandler(null);
      rethrow;
    }
  }

  Future<void> stop() async {
    if (!_active && !isSupported) return;
    _active = false;
    _onKey = null;
    _onReleaseChord = null;
    _onLocalShortcut = null;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
    _channel.setMethodCallHandler(null);
  }

  Future<dynamic> _onPlatformCall(MethodCall call) async {
    switch (call.method) {
      case 'key':
        final args = call.arguments;
        if (args is! Map) return null;
        final keysym = (args['keysym'] as num?)?.toInt();
        final down = args['down'] as bool? ?? false;
        final physical = (args['physical'] as num?)?.toInt() ?? keysym ?? 0;
        if (keysym != null) {
          _onKey?.call(keysym, down, physical);
        }
        return null;
      case 'releaseChord':
        _onReleaseChord?.call();
        return null;
      case 'localShortcut':
        final args = call.arguments;
        if (args is Map) {
          final kind = args['kind'] as String?;
          if (kind != null) _onLocalShortcut?.call(kind);
        }
        return null;
      default:
        throw MissingPluginException(call.method);
    }
  }
}

/// Right ⌘ (macOS) / Right Ctrl (Windows/Linux) release chord.
bool isExclusiveReleaseKey(LogicalKeyboardKey key) {
  if (kIsWeb) return false;
  if (Platform.isMacOS) {
    return key == LogicalKeyboardKey.metaRight;
  }
  return key == LogicalKeyboardKey.controlRight;
}
