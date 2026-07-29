import 'dart:io';
import 'dart:math' as math;

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
///
/// Modals (auth dialog, etc.) must call [pauseForModal] / [resumeAfterModal] so
/// the CGEventTap does not swallow TextField input.
class ExclusiveGrab {
  ExclusiveGrab({
    MethodChannel? channel,
    bool? forceSupported,
  })  : _channel = channel ?? const MethodChannel(_channelName),
        _forceSupported = forceSupported;

  final MethodChannel _channel;
  final bool? _forceSupported;

  /// Process-wide: nested modal pause depth. Tap is off while > 0.
  static int _uiPauseDepth = 0;

  /// Last grab that called [start] and still wants to be active.
  static ExclusiveGrab? _activeInstance;

  var _wantActive = false;
  var _nativeActive = false;
  void Function(int keysym, bool down, int physical)? _onKey;
  VoidCallback? _onReleaseChord;
  void Function(String kind)? _onLocalShortcut;

  bool get isSupported =>
      _forceSupported ??
      (!kIsWeb && (Platform.isMacOS || Platform.isWindows));

  /// True while the native tap is running (not merely "wanted").
  bool get isActive => _nativeActive;

  /// True if this instance still wants grab when modals close.
  bool get wantsActive => _wantActive;

  @visibleForTesting
  static int get debugUiPauseDepth => _uiPauseDepth;

  @visibleForTesting
  static ExclusiveGrab? get debugActiveInstance => _activeInstance;

  @visibleForTesting
  static void debugResetModalPause() {
    _uiPauseDepth = 0;
    _activeInstance = null;
  }

  /// Pause native grab for a modal UI (auth dialog, etc.). Nestable.
  static Future<void> pauseForModal() async {
    _uiPauseDepth++;
    await _activeInstance?._stopNative(clearCallbacks: false);
  }

  /// Resume after [pauseForModal]. Restarts tap when depth hits 0 and grab is wanted.
  static Future<void> resumeAfterModal() async {
    _uiPauseDepth = math.max(0, _uiPauseDepth - 1);
    if (_uiPauseDepth > 0) return;
    final g = _activeInstance;
    if (g != null && g._wantActive) {
      await g._startNative();
    }
  }

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
    _wantActive = true;
    _activeInstance = this;
    if (_uiPauseDepth > 0) return;
    await _startNative();
  }

  Future<void> stop() async {
    _wantActive = false;
    if (_activeInstance == this) {
      _activeInstance = null;
    }
    await _stopNative(clearCallbacks: true);
  }

  Future<void> _startNative() async {
    if (!isSupported || _nativeActive) return;
    _channel.setMethodCallHandler(_onPlatformCall);
    try {
      await _channel.invokeMethod<void>('start');
      _nativeActive = true;
    } on MissingPluginException {
      _nativeActive = false;
      _channel.setMethodCallHandler(null);
    } catch (_) {
      _nativeActive = false;
      _channel.setMethodCallHandler(null);
      rethrow;
    }
  }

  Future<void> _stopNative({required bool clearCallbacks}) async {
    final wasActive = _nativeActive;
    _nativeActive = false;
    if (clearCallbacks) {
      _onKey = null;
      _onReleaseChord = null;
      _onLocalShortcut = null;
    }
    if (wasActive) {
      try {
        await _channel.invokeMethod<void>('stop');
      } catch (_) {}
    }
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
