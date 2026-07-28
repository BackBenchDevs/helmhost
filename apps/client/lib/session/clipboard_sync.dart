import 'dart:async';

import 'package:flutter/services.dart';

/// TigerVNC-style SendClipboard: push host clipboard → ClientCutText on change.
///
/// Polls [Clipboard] while [enabled]. Suppresses echoes after ServerCutText
/// updates the host clipboard via [noteServerText].
class ClipboardSync {
  ClipboardSync({
    required void Function(String text) sendToRemote,
    this.pollInterval = const Duration(milliseconds: 400),
    Future<ClipboardData?> Function(String format)? getData,
  })  : _sendToRemote = sendToRemote,
        _getData = getData ?? Clipboard.getData;

  final void Function(String text) _sendToRemote;
  final Duration pollInterval;
  final Future<ClipboardData?> Function(String format) _getData;

  Timer? _timer;
  String? _lastSeen;
  String? _lastSent;
  /// Text we applied from ServerCutText — do not re-send until host changes again.
  String? _suppressEcho;

  bool get isRunning => _timer != null;

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(pollInterval, (_) => unawaited(tick()));
    unawaited(tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Call after writing ServerCutText into the host clipboard.
  void noteServerText(String text) {
    _suppressEcho = text;
    _lastSeen = text;
  }

  /// Call after an explicit Paste flush so the poller does not double-send.
  void noteSent(String text) {
    _lastSent = text;
    _lastSeen = text;
    _suppressEcho = null;
  }

  /// One poll cycle (also used by tests).
  Future<void> tick() async {
    final data = await _getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      _lastSeen = text ?? '';
      return;
    }
    if (text == _lastSeen) return;
    _lastSeen = text;
    if (text == _suppressEcho) {
      // Host clipboard still mirrors the last ServerCutText — do not echo.
      return;
    }
    if (text == _lastSent) return;
    _suppressEcho = null;
    _lastSent = text;
    _sendToRemote(text);
  }
}
