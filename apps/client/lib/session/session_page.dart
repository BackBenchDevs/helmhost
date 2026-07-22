import 'dart:async';
import 'dart:ui' as ui;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../bridge.dart';
import '../keysyms.dart';
import '../library/auth_dialog.dart';
import '../logging/logger.dart';
import '../prefs.dart';
import '../session_helpers.dart';
import '../storage/credential_store.dart';
import '../thumbs.dart';
import 'buffering_overlay.dart';
import 'credentials.dart';
import 'fb_texture.dart';
import 'paint_helpers.dart';
import 'session_ipc.dart';
import 'session_link_stats.dart';
import 'session_shortcuts.dart';
import 'session_status_bar.dart';

class SessionPage extends StatefulWidget {
  SessionPage({
    super.key,
    required this.sessionId,
    required this.title,
    required this.host,
    required this.port,
    this.entryId,
    this.profileId,
    this.username,
    this.preferVencrypt = false,
    this.acceptInvalidCerts = false,
    this.closeOnExit = true,
    this.active = true,
    this.prefs,
    this.bandwidthPreset = BandwidthPreset.balanced,
    this.qualityLevel,
    this.compressLevel,
    ILogger? logger,
  }) : logger = logger ?? defaultLogger(module: 'session');

  final int sessionId;
  final String title;
  final String host;
  final int port;
  final String? entryId;
  final String? profileId;
  final String? username;
  final bool preferVencrypt;
  final bool acceptInvalidCerts;
  final bool closeOnExit;
  /// When false (inactive IndexedStack tab), pause poll/timers.
  final bool active;
  final AppPrefs? prefs;
  final BandwidthPreset bandwidthPreset;
  final int? qualityLevel;
  final int? compressLevel;
  final ILogger logger;

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> with WindowListener {
  static const _firstFrameTimeout = Duration(seconds: 15);
  static const _reconnectTimeout = Duration(seconds: 15);
  static const _maxReconnectAttempts = 3;
  static const _backoff = [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
  ];

  late final HelmBridge _bridge;
  late int _sessionId;
  Timer? _pollTimer;
  Timer? _firstFrameTimer;
  Timer? _statsUiTimer;
  ui.Image? _frame;
  FbTextureController? _fbTex;
  int? _textureId;
  int _fw = 0;
  int _fh = 0;
  bool _grabbed = true;
  bool _dirty = false;
  bool _pulling = false;
  bool _paintScheduled = false;
  DamageRect? _pendingDamage;
  bool _hadTextureSuccess = false;
  int _textureFailStreak = 0;
  int? _pendingPtrX;
  int? _pendingPtrY;
  int _pendingPtrButtons = 0;
  int _lastSentButtons = 0;
  bool _pointerFlushScheduled = false;
  bool _hubNotifiedEnd = false;
  bool _sessionTornDown = false;
  bool _windowClosing = false;
  bool _reconnectDialogShowing = false;
  bool _pollStoppedForStale = false;
  String? _lastError;
  SessionConnState _connState = SessionConnState.connecting;
  int _reconnectAttempt = 0;
  String? _sessionPassword;
  String? _sessionUsername;
  final _linkStats = SessionLinkStats();
  final _creds = createCredentialStore();
  final _viewKey = GlobalKey();
  final _focusNode = FocusNode();
  final _downKeysyms = <int, int>{};
  /// Physical keys swallowed for local shortcuts (no RFB key-up).
  final _swallowedPhys = <int>{};
  late ViewScaleMode _scaleMode;
  BandwidthPreset _bandwidthPreset = BandwidthPreset.balanced;
  int? _qualityLevel;
  int? _compressLevel;
  Timer? _thumbTimer;
  Timer? _resizeDebounce;
  int _lastReqW = 0;
  int _lastReqH = 0;
  static final bool _paintTrace =
      const bool.fromEnvironment('HELMHOST_PAINT_TRACE', defaultValue: false);

  /// In-hub tab: keep RFB alive across tab switches; no native Texture paint.
  bool get _embedded => !widget.closeOnExit;

  @override
  void initState() {
    super.initState();
    _sessionId = widget.sessionId;
    _scaleMode = widget.prefs?.viewScaleMode ?? ViewScaleMode.fit;
    _bandwidthPreset = widget.bandwidthPreset;
    _qualityLevel = widget.qualityLevel;
    _compressLevel = widget.compressLevel;
    _bridge = HelmBridge.open();
    if (widget.active) {
      _startActiveSession();
    }
    if (!_embedded) {
      unawaited(_initTexture());
    }
    windowManager.addListener(this);
    if (widget.closeOnExit) {
      unawaited(windowManager.setPreventClose(true));
    }
  }

  @override
  void didUpdateWidget(covariant SessionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      _sessionId = widget.sessionId;
    }
    if (oldWidget.active == widget.active) return;
    if (widget.active) {
      _resumeActiveSession();
    } else {
      _pauseInactiveSession();
    }
  }

  void _startActiveSession() {
    _pollStoppedForStale = false;
    try {
      _bridge.grab(_sessionId);
    } catch (_) {}
    _ensureTimers();
    _armFirstFrameTimeout();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active) {
        _focusNode.requestFocus();
        unawaited(_pullFramebufferIfReady());
      }
    });
  }

  void _resumeActiveSession() {
    if (_pollStoppedForStale ||
        _connState == SessionConnState.disconnected ||
        _connState == SessionConnState.timedOut) {
      // Stay paused until user reconnects.
      if (mounted) setState(() {});
      return;
    }
    _startActiveSession();
  }

  void _pauseInactiveSession() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _thumbTimer?.cancel();
    _thumbTimer = null;
    _statsUiTimer?.cancel();
    _statsUiTimer = null;
    _firstFrameTimer?.cancel();
    _firstFrameTimer = null;
    _resizeDebounce?.cancel();
    _releaseAllKeys();
    try {
      _bridge.releaseFocus();
    } catch (_) {}
  }

  void _ensureTimers() {
    _pollTimer?.cancel();
    _pollTimer =
        Timer.periodic(const Duration(milliseconds: 8), (_) => _pollEvents());
    _thumbTimer?.cancel();
    _thumbTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _captureThumb());
    _statsUiTimer?.cancel();
    _statsUiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.active && _connState == SessionConnState.live) {
        setState(() {});
      }
    });
  }

  Future<void> _pullFramebufferIfReady() async {
    if (!mounted || !widget.active) return;
    try {
      final (w, h) = _bridge.fbSize(_sessionId);
      if (w <= 0 || h <= 0) return;
      _fw = w;
      _fh = h;
      await _pullFramebuffer();
    } catch (_) {}
  }

  void _armFirstFrameTimeout() {
    _firstFrameTimer?.cancel();
    _firstFrameTimer = Timer(_firstFrameTimeout, _onFirstFrameTimeout);
  }

  void _onFirstFrameTimeout() {
    if (!mounted) return;
    if (_connState != SessionConnState.connecting &&
        _connState != SessionConnState.reconnecting) {
      return;
    }
    if (_hasFramebuffer) return;
    if (_connState == SessionConnState.reconnecting) {
      // Attempt timed out — continue reconnect loop from caller.
      return;
    }
    setState(() {
      _connState = SessionConnState.timedOut;
      _lastError = 'Timed out waiting for framebuffer';
    });
    unawaited(_showReconnectDialog(reason: _lastError!));
  }

  bool get _hasFramebuffer =>
      (_fw > 0 && _fh > 0) && (_textureId != null || _frame != null);

  Future<void> _initTexture() async {
    if (_embedded) return;
    final tex = await FbTextureController.create();
    if (!mounted || tex == null) return;
    setState(() {
      _fbTex = tex;
      _textureId = tex.textureId;
    });
  }

  /// Stop UI work but leave the native RFB session running (detach edge cases).
  void _softDisposeEmbedded() {
    _pauseInactiveSession();
    unawaited(_fbTex?.dispose() ?? Future<void>.value());
    _fbTex = null;
    _textureId = null;
  }

  Future<void> _notifyHubEnded({String reason = 'ended'}) async {
    if (_hubNotifiedEnd) return;
    _hubNotifiedEnd = true;
    await notifyHub(kMethodSessionEnded, {
      'sessionId': _sessionId,
      'host': widget.host,
      'port': widget.port,
      'reason': reason,
    });
  }

  Future<void> _notifyHubReplaced(int oldId, int newId) async {
    _hubNotifiedEnd = false;
    await notifyHub(kMethodSessionReplaced, {
      'oldId': oldId,
      'newId': newId,
      'host': widget.host,
      'port': widget.port,
    });
  }

  bool _isNativeSessionAlive() {
    try {
      _bridge.fbSize(_sessionId);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void onWindowClose() async {
    // Hub-embedded sessions: hub owns the window close path.
    if (!widget.closeOnExit) return;
    if (_windowClosing) return;

    final skipConfirm = _sessionTornDown ||
        _connState == SessionConnState.disconnected ||
        _connState == SessionConnState.timedOut ||
        !_isNativeSessionAlive();

    if (!skipConfirm && mounted) {
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Disconnect session?'),
          content: Text(
            'Close this window and disconnect from ${widget.host}:${widget.port}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Disconnect'),
            ),
          ],
        ),
      );
      if (ok != true) {
        // Keep window open; re-arm prevent-close.
        await windowManager.setPreventClose(true);
        return;
      }
    }

    _windowClosing = true;
    widget.logger.info('session window closing — disconnecting', {
      'sessionId': _sessionId,
      'host': widget.host,
      'port': widget.port,
    });
    await _teardownSession(reason: 'window_closed');
    // NEVER call windowManager.destroy() here — on macOS that is
    // NSApp.terminate and kills Hub + every session window.
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  /// Disconnect RFB + notify Hub. Idempotent.
  Future<void> _teardownSession({required String reason}) async {
    if (_sessionTornDown) return;
    _sessionTornDown = true;
    _pollTimer?.cancel();
    _thumbTimer?.cancel();
    _resizeDebounce?.cancel();
    _firstFrameTimer?.cancel();
    _statsUiTimer?.cancel();
    try {
      _captureThumb();
    } catch (_) {}
    await _notifyHubEnded(reason: reason);
    _releaseAllKeys();
    if (widget.closeOnExit) {
      try {
        _bridge.close(_sessionId);
      } catch (e) {
        widget.logger.warn('session close failed', {
          'sessionId': _sessionId,
          'error': '$e',
        });
      }
    }
    try {
      _bridge.releaseFocus();
    } catch (_) {}
    try {
      await _fbTex?.dispose();
    } catch (_) {}
    _fbTex = null;
  }

  @override
  void onWindowBlur() {
    if (!mounted) return;
    if (_grabbed) _setGrabbed(false);
  }

  @override
  void onWindowFocus() {
    if (!mounted || !widget.active) return;
    if (_connState != SessionConnState.live) return;
    if (!_grabbed) _setGrabbed(true);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    if (_embedded) {
      // Tab switch remounts SessionPage — do not end the RFB session.
      _softDisposeEmbedded();
    } else {
      // OS close goes through [onWindowClose]; dispose is a safety net.
      if (!_sessionTornDown) {
        unawaited(_teardownSession(reason: 'disposed'));
      }
    }
    _focusNode.dispose();
    _frame?.dispose();
    super.dispose();
  }

  void _releaseAllKeys() {
    for (final sym in _downKeysyms.values) {
      try {
        _bridge.sendKey(_sessionId, false, sym);
      } catch (_) {}
    }
    _downKeysyms.clear();
    _swallowedPhys.clear();
  }

  void _setGrabbed(bool grab) {
    if (grab) {
      _bridge.grab(_sessionId);
      _focusNode.requestFocus();
    } else {
      _pendingPtrButtons = 0;
      _flushPointerNow();
      _releaseAllKeys();
      _bridge.releaseFocus();
    }
    setState(() => _grabbed = grab);
  }

  Future<void> _setScaleMode(ViewScaleMode m) async {
    setState(() => _scaleMode = m);
    await widget.prefs?.setViewScaleMode(m);
    if (m.usesRemoteResize) {
      _scheduleRemoteResize();
    }
  }

  void _onViewSize(Size size) {
    if (!_scaleMode.usesRemoteResize) return;
    final w = size.width.round();
    final h = size.height.round();
    if (w <= 0 || h <= 0) return;
    if (w == _lastReqW && h == _lastReqH) return;
    _lastReqW = w;
    _lastReqH = h;
    _scheduleRemoteResize();
  }

  void _scheduleRemoteResize() {
    if (!_scaleMode.usesRemoteResize) return;
    _resizeDebounce?.cancel();
    _resizeDebounce = Timer(const Duration(milliseconds: 100), () {
      if (!mounted || !_scaleMode.usesRemoteResize) return;
      final box = _viewKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final w = box.size.width.round();
      final h = box.size.height.round();
      if (w <= 0 || h <= 0) return;
      if (w == _fw && h == _fh) return;
      try {
        _bridge.requestDesktopSize(_sessionId, w, h);
      } catch (e) {
        widget.logger.warn('requestDesktopSize failed', {'error': '$e'});
      }
    });
  }

  Future<void> _captureThumb() async {
    final id = widget.entryId ?? widget.title;
    await saveSessionThumb(_bridge, id, _sessionId);
  }

  void _onBell() {
    SystemSound.play(SystemSoundType.alert);
  }

  Future<void> _onClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> _pasteToRemote() async {
    if (!_grabbed) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    try {
      _bridge.sendClipboard(_sessionId, text);
    } catch (_) {}
  }

  void _markDirty([DamageRect? rect]) {
    _linkStats.recordFrame();
    if (rect != null) {
      _pendingDamage = unionDamage(_pendingDamage, rect);
    } else {
      // Full-frame (resize / unknown).
      _pendingDamage = null;
    }
    _dirty = true;
    _schedulePaint();
  }

  void _onFirstFrameReady() {
    _firstFrameTimer?.cancel();
    if (_connState != SessionConnState.live) {
      setState(() {
        _connState = SessionConnState.live;
        _lastError = null;
        _reconnectAttempt = 0;
      });
    }
  }

  void _schedulePaint() {
    if (_paintScheduled || !_dirty) return;
    _paintScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _paintScheduled = false;
      unawaited(_paintIfDirty());
    });
    SchedulerBinding.instance.scheduleFrame();
  }

  Future<void> _paintIfDirty() async {
    if (!_dirty || _pulling) return;
    _dirty = false;
    _pulling = true;
    try {
      await _pullFramebuffer();
    } catch (e) {
      if (mounted) {
        setState(() => _lastError = e.toString());
      }
    } finally {
      _pulling = false;
      if (_dirty) _schedulePaint();
    }
  }

  Future<void> _pullFramebuffer() async {
    final sw = Stopwatch()..start();
    final (w, h) = _bridge.fbSize(_sessionId);
    if (w <= 0 || h <= 0) return;
    _fw = w;
    _fh = h;

    final damage = _pendingDamage;
    _pendingDamage = null;

    final tex = _fbTex;
    if (tex != null) {
      final presented = damage == null || damage.isEmpty
          ? await tex.present(_sessionId)
          : await tex.present(
              _sessionId,
              x: damage.x,
              y: damage.y,
              w: damage.w,
              h: damage.h,
            );
      if (!mounted) return;
      if (presented) {
        _hadTextureSuccess = true;
        _textureFailStreak = 0;
        _onFirstFrameReady();
        if (_textureId != tex.textureId || _frame != null) {
          setState(() {
            _textureId = tex.textureId;
            _frame?.dispose();
            _frame = null;
            _lastError = null;
          });
        }
        if (kDebugMode && _paintTrace && sw.elapsedMilliseconds > 16) {
          widget.logger.debug('paint slow', {
            'w': w,
            'h': h,
            'ms': sw.elapsedMilliseconds,
            'path': 'texture',
            if (damage != null) 'dmg': '${damage.w}x${damage.h}',
          });
        }
        return;
      }
      _textureFailStreak++;
      final fallback = shouldFallbackToDartDecode(
        embedded: _embedded,
        hadTextureSuccess: _hadTextureSuccess,
        presentOk: false,
        failStreak: _textureFailStreak,
      );
      if (!fallback) {
        // Soft-skip — retry on next dirty/frame.
        if (damage != null) {
          _pendingDamage = unionDamage(_pendingDamage, damage);
        }
        _dirty = true;
        return;
      }
    }

    await _pullFramebufferDecode(w, h, sw);
  }

  Future<void> _pullFramebufferDecode(int w, int h, Stopwatch sw) async {
    final pixels = _bridge.fbCopy(_sessionId, w, h);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      w,
      h,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final img = await completer.future;
    if (!mounted) {
      img.dispose();
      return;
    }
    _onFirstFrameReady();
    setState(() {
      _frame?.dispose();
      _frame = img;
      // Prefer RawImage until texture present works.
      _textureId = null;
      _lastError = null;
    });
    if (kDebugMode && _paintTrace && sw.elapsedMilliseconds > 16) {
      widget.logger.debug('paint slow', {
        'w': w,
        'h': h,
        'ms': sw.elapsedMilliseconds,
        'path': 'decode',
      });
    }
  }

  void _pollEvents() {
    if (!mounted || !widget.active || _pollStoppedForStale) return;
    try {
      for (var i = 0; i < 64; i++) {
        final ev = _bridge.pollEvent(_sessionId);
        final type = ev['type'] as String? ?? 'none';
        if (type == 'none') break;
        if (type == 'desktop_resize') {
          _fw = (ev['w'] as num).toInt();
          _fh = (ev['h'] as num).toInt();
          _hadTextureSuccess = false; // force full present after resize
          _markDirty(); // full frame
        } else if (type == 'framebuffer_dirty') {
          final dx = (ev['x'] as num?)?.toInt();
          final dy = (ev['y'] as num?)?.toInt();
          final dw = (ev['w'] as num?)?.toInt();
          final dh = (ev['h'] as num?)?.toInt();
          if (dx != null && dy != null && dw != null && dh != null && dw > 0 && dh > 0) {
            _markDirty(DamageRect(x: dx, y: dy, w: dw, h: dh));
          } else {
            _markDirty();
          }
        } else if (type == 'bell') {
          _onBell();
        } else if (type == 'clipboard') {
          unawaited(_onClipboard(ev['text'] as String? ?? ''));
        } else if (type == 'disconnected' || type == 'error') {
          final msg = type == 'error'
              ? (ev['message'] as String? ?? ev.toString())
              : 'Disconnected';
          if (shouldStopPollingOnEvent(ev)) {
            _stopPollingForStale();
          }
          // One log line — not every poll tick.
          if (_connState != SessionConnState.disconnected) {
            widget.logger.warn(type, {
              'sessionId': _sessionId,
              'message': msg,
            });
          }
          unawaited(_handleDisconnect(msg));
          break;
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _lastError = e.toString());
      }
    }
  }

  void _stopPollingForStale() {
    _pollStoppedForStale = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    _thumbTimer?.cancel();
    _thumbTimer = null;
    _statsUiTimer?.cancel();
    _statsUiTimer = null;
    _firstFrameTimer?.cancel();
    _firstFrameTimer = null;
  }

  Future<void> _handleDisconnect(String msg) async {
    if (_connState == SessionConnState.reconnecting) return;
    if (_connState == SessionConnState.disconnected) return;

    final unknown = isUnknownSessionMessage(msg);
    // Embedded + unknown session: keep hub tab so user can reconnect.
    if (!(_embedded && unknown)) {
      await _notifyHubEnded(reason: msg);
    }
    if (!mounted) return;
    setState(() {
      _connState = SessionConnState.disconnected;
      _lastError = unknown ? 'Session ended' : msg;
    });
    final auto = shouldAutoReconnect(
      prefEnabled: widget.prefs?.autoReconnectOnDrop ?? false,
      embedded: _embedded,
      unknownSession: unknown,
    );
    if (auto) {
      unawaited(_runReconnectLoop());
    } else {
      await _showReconnectDialog(reason: _lastError!);
    }
  }

  Future<void> _showReconnectDialog({required String reason}) async {
    if (!mounted || _reconnectDialogShowing) return;
    _reconnectDialogShowing = true;
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(_connState == SessionConnState.timedOut
            ? 'Connection timed out'
            : 'Disconnected'),
        content: Text(reason),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'close'),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'reconnect'),
            child: const Text('Reconnect'),
          ),
        ],
      ),
    );
    _reconnectDialogShowing = false;
    if (!mounted) return;
    if (action == 'reconnect') {
      unawaited(_runReconnectLoop());
    } else if (action == 'close') {
      if (_embedded) {
        await _notifyHubEnded(reason: 'user_closed');
      } else {
        await windowCloseSelf();
      }
    }
  }

  Future<void> windowCloseSelf() async {
    // Prefer prevent-close path so [onWindowClose] disconnects cleanly.
    if (widget.closeOnExit) {
      try {
        await windowManager.close();
        return;
      } catch (_) {}
    }
    try {
      final c = await WindowController.fromCurrentEngine();
      await c.invokeMethod(kMethodWindowClose);
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> _runReconnectLoop() async {
    _pollStoppedForStale = false;
    setState(() {
      _connState = SessionConnState.reconnecting;
      _reconnectAttempt = 0;
      _lastError = null;
      // Keep last frame under BufferingOverlay (no black flash).
      _linkStats.reset();
    });
    _ensureTimers();

    for (var i = 0; i < _maxReconnectAttempts; i++) {
      if (!mounted) return;
      setState(() => _reconnectAttempt = i + 1);
      if (i > 0) {
        await Future<void>.delayed(_backoff[i - 1]);
      }
      final result = await _attemptReconnect();
      if (result == _ReconnectOutcome.success) return;
      if (result == _ReconnectOutcome.authCancelled) {
        if (!mounted) return;
        setState(() {
          _connState = SessionConnState.disconnected;
          _lastError = 'Password required';
        });
        await _showReconnectDialog(reason: _lastError!);
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      _connState = SessionConnState.disconnected;
      _lastError = 'Reconnect failed after $_maxReconnectAttempts attempts';
    });
    await _showReconnectDialog(reason: _lastError!);
  }

  Future<_ReconnectOutcome> _attemptReconnect() async {
    final oldId = _sessionId;
    await _notifyHubEnded(reason: 'reconnect');
    try {
      _bridge.close(oldId);
    } catch (_) {}

    final entryId = widget.entryId ?? sessionKey(widget.host, widget.port);
    String? password;
    try {
      password = await resolvePassword(
        store: _creds,
        entryId: entryId,
        sessionPassword: _sessionPassword,
        profileId: widget.profileId,
      );
    } catch (_) {}

    try {
      return await _connectAfterReconnect(
        oldId: oldId,
        username: _sessionUsername ?? widget.username,
        password: password,
      );
    } on StateError catch (e) {
      if (!isAuthError(e)) {
        widget.logger.error('reconnect failed', {'error': '$e'});
        if (mounted) {
          setState(() => _lastError = e.toString());
        }
        return _ReconnectOutcome.failed;
      }
      if (!mounted) return _ReconnectOutcome.authCancelled;
      setState(() => _lastError = authErrorLabel(e));
      final need = parseAuthNeed(e.message);
      final creds = await showAuthDialog(
        context,
        need: need,
        initialUsername: _sessionUsername ?? widget.username,
      );
      if (creds == null ||
          (creds.password == null || creds.password!.isEmpty)) {
        return _ReconnectOutcome.authCancelled;
      }
      _sessionPassword = creds.password;
      if (creds.username != null && creds.username!.isNotEmpty) {
        _sessionUsername = creds.username;
      }
      if (creds.savePermanently) {
        try {
          await persistEntryCredentials(
            _creds,
            entryId,
            password: creds.password,
            savePassword: true,
          );
        } catch (_) {}
      }
      try {
        return await _connectAfterReconnect(
          oldId: oldId,
          username: _sessionUsername ?? widget.username,
          password: _sessionPassword,
        );
      } catch (e2) {
        widget.logger.error('reconnect failed', {'error': '$e2'});
        if (mounted) {
          setState(() {
            _lastError = isAuthError(e2) ? authErrorLabel(e2) : e2.toString();
          });
        }
        return isAuthError(e2)
            ? _ReconnectOutcome.authCancelled
            : _ReconnectOutcome.failed;
      }
    } catch (e) {
      widget.logger.error('reconnect failed', {'error': '$e'});
      if (mounted) {
        setState(() => _lastError = e.toString());
      }
      return _ReconnectOutcome.failed;
    }
  }

  Future<_ReconnectOutcome> _connectAfterReconnect({
    required int oldId,
    String? username,
    String? password,
  }) async {
    final newId = _bridge.connect(
      widget.host,
      widget.port,
      username: username,
      password: password,
      preferVencrypt: widget.preferVencrypt,
      acceptInvalidCerts: widget.acceptInvalidCerts,
      bandwidthPreset: _bandwidthPreset.wireCode,
      qualityLevel: _qualityLevel,
      compressLevel: _compressLevel,
    );
    _bridge.grab(newId);
    await _notifyHubReplaced(oldId, newId);
    if (!mounted) return _ReconnectOutcome.failed;
    setState(() {
      _sessionId = newId;
      _hubNotifiedEnd = false;
      _pollStoppedForStale = false;
      _connState = SessionConnState.connecting;
      _lastError = null;
    });
    _ensureTimers();
    _armFirstFrameTimeout();

    final deadline = DateTime.now().add(_reconnectTimeout);
    while (mounted && DateTime.now().isBefore(deadline)) {
      if (_hasFramebuffer || _connState == SessionConnState.live) {
        return _ReconnectOutcome.success;
      }
      if (_connState == SessionConnState.disconnected) {
        return _ReconnectOutcome.failed;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return (_hasFramebuffer || _connState == SessionConnState.live)
        ? _ReconnectOutcome.success
        : _ReconnectOutcome.failed;
  }

  (int, int)? _remoteXY(Offset global) {
    final box = _viewKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || _fw <= 0 || _fh <= 0) return null;
    final local = box.globalToLocal(global);
    final vw = box.size.width;
    final vh = box.size.height;
    if (vw <= 0 || vh <= 0) return null;

    final scale = (vw / _fw < vh / _fh) ? vw / _fw : vh / _fh;
    final ox = (vw - _fw * scale) / 2;
    final oy = (vh - _fh * scale) / 2;
    final rx = ((local.dx - ox) / scale).round();
    final ry = ((local.dy - oy) / scale).round();
    if (rx < 0 || ry < 0 || rx >= _fw || ry >= _fh) return null;
    return (rx, ry);
  }

  double _scrollAccX = 0;
  double _scrollAccY = 0;
  Offset? _lastPointerGlobal;

  void _onPointer(Offset global, int buttons) {
    if (!_grabbed || _connState != SessionConnState.live) return;
    _lastPointerGlobal = global;
    _focusNode.requestFocus();
    final xy = _remoteXY(global);
    if (xy == null) return;
    final immediate = shouldFlushPointerImmediate(
      buttons: buttons,
      lastButtons: _lastSentButtons,
    );
    _pendingPtrX = xy.$1;
    _pendingPtrY = xy.$2;
    _pendingPtrButtons = buttons;
    if (immediate) {
      _flushPointerNow();
      return;
    }
    _schedulePointerFlush();
  }

  void _schedulePointerFlush() {
    if (_pointerFlushScheduled) return;
    _pointerFlushScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _pointerFlushScheduled = false;
      _flushPointerNow();
    });
    SchedulerBinding.instance.scheduleFrame();
  }

  void _flushPointerNow() {
    final x = _pendingPtrX;
    final y = _pendingPtrY;
    if (x == null || y == null) return;
    try {
      _bridge.sendPointer(_sessionId, x, y, _pendingPtrButtons);
      _lastSentButtons = _pendingPtrButtons;
    } catch (_) {}
  }

  void _flushWheel(Offset global) {
    const step = 20.0;
    void click(int mask) {
      final pos =
          _remoteXY(global) != null ? global : (_lastPointerGlobal ?? global);
      _onPointer(pos, mask);
      _onPointer(pos, 0);
    }

    while (_scrollAccY <= -step) {
      click(1 << 3);
      _scrollAccY += step;
    }
    while (_scrollAccY >= step) {
      click(1 << 4);
      _scrollAccY -= step;
    }
    while (_scrollAccX <= -step) {
      click(1 << 5);
      _scrollAccX += step;
    }
    while (_scrollAccX >= step) {
      click(1 << 6);
      _scrollAccX -= step;
    }
  }

  void _onScroll(PointerScrollEvent e) {
    if (!_grabbed) return;
    _scrollAccX -= e.scrollDelta.dx;
    _scrollAccY -= e.scrollDelta.dy;
    _flushWheel(e.position);
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent e) {
    if (!_grabbed) return;
    _scrollAccX -= e.panDelta.dx;
    _scrollAccY -= e.panDelta.dy;
    _flushWheel(e.position);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_grabbed || _connState != SessionConnState.live) {
      return KeyEventResult.ignored;
    }

    final phys = event.physicalKey.usbHidUsage;
    final down = event is KeyDownEvent || event is KeyRepeatEvent;

    if (!down) {
      if (_swallowedPhys.remove(phys)) {
        return KeyEventResult.handled;
      }
      final sym = _downKeysyms.remove(phys);
      if (sym == null) return KeyEventResult.ignored;
      try {
        _bridge.sendKey(_sessionId, false, sym);
      } catch (_) {}
      return KeyEventResult.handled;
    }

    if (event is KeyDownEvent) {
      final local = classifySessionLocalKeyEvent(event);
      if (local != null) {
        _swallowedPhys.add(phys);
        if (local == SessionLocalShortcut.pasteToRemote) {
          unawaited(_pasteToRemote());
        }
        // consume (⌘C / ⌘X): remote→local copy is ServerCutText → clipboard
        return KeyEventResult.handled;
      }
    }

    if (event is KeyRepeatEvent) {
      if (_swallowedPhys.contains(phys)) {
        return KeyEventResult.handled;
      }
      final sym = _downKeysyms[phys];
      if (sym == null) return KeyEventResult.ignored;
      try {
        _bridge.sendKey(_sessionId, true, sym);
      } catch (_) {}
      return KeyEventResult.handled;
    }

    final sym = keysymForKeyEvent(event);
    if (sym == null) return KeyEventResult.ignored;
    _downKeysyms[phys] = sym;
    try {
      _bridge.sendKey(_sessionId, true, sym);
    } catch (_) {}
    return KeyEventResult.handled;
  }

  Widget _frameChild() {
    final showBuffer = _connState == SessionConnState.connecting ||
        _connState == SessionConnState.reconnecting;
    final tid = _textureId;
    Widget content;
    if (tid != null && _fw > 0 && _fh > 0) {
      content = SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: _fw.toDouble(),
            height: _fh.toDouble(),
            child: Texture(textureId: tid),
          ),
        ),
      );
    } else if (_frame != null) {
      content = SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: _fw.toDouble(),
            height: _fh.toDouble(),
            child: RawImage(
              image: _frame,
              width: _fw.toDouble(),
              height: _fh.toDouble(),
              fit: BoxFit.fill,
              filterQuality: FilterQuality.low,
            ),
          ),
        ),
      );
    } else {
      content = const SizedBox.expand();
    }

    if (!showBuffer &&
        (_connState == SessionConnState.disconnected ||
            _connState == SessionConnState.timedOut) &&
        !_hasFramebuffer) {
      return Center(
        child: Text(
          _lastError ?? _connState.label,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        content,
        if (showBuffer)
          BufferingOverlay(
            message: _connState == SessionConnState.reconnecting
                ? 'Reconnecting… ($_reconnectAttempt/$_maxReconnectAttempts)'
                : 'Connecting…',
            detail: _lastError,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: null,
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKey,
        child: MouseRegion(
          cursor: _grabbed ? SystemMouseCursors.none : SystemMouseCursors.basic,
          child: Listener(
            onPointerDown: (e) => _onPointer(e.position, e.buttons),
            onPointerMove: (e) => _onPointer(e.position, e.buttons),
            onPointerUp: (e) => _onPointer(e.position, 0),
            onPointerHover: (e) => _onPointer(e.position, 0),
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) _onScroll(e);
            },
            onPointerPanZoomUpdate: _onPanZoomUpdate,
              child: ColoredBox(
                color: Colors.black,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _onViewSize(Size(constraints.maxWidth, constraints.maxHeight));
                    });
                    return KeyedSubtree(
                      key: _viewKey,
                      child: _frameChild(),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: SessionStatusBar(
          connState: _connState,
          linkStats: _linkStats,
          host: widget.host,
          port: widget.port,
          scaleMode: _scaleMode,
          grabbed: _grabbed,
          onPaste: _pasteToRemote,
          onScaleChanged: _setScaleMode,
          onToggleGrab: () => _setGrabbed(!_grabbed),
          errorText: _lastError,
          reconnectAttempt: _reconnectAttempt,
          maxReconnectAttempts: _maxReconnectAttempts,
          autoReconnect: widget.prefs?.autoReconnectOnDrop ?? false,
          onAutoReconnectChanged: widget.prefs == null
              ? null
              : (v) async {
                  await widget.prefs!.setAutoReconnectOnDrop(v);
                  if (mounted) setState(() {});
                },
          bandwidthPresetLabel: _bandwidthPreset.label,
          bandwidthChoices: [
            for (final p in BandwidthPreset.values) p.label,
          ],
          onBandwidthPreset: (label) {
            final p = BandwidthPresetX.fromLabel(label);
            if (p != null) {
              setState(() => _bandwidthPreset = p);
              // Applied on next reconnect (live re-advertise may be unavailable).
            }
          },
        ),
    );
  }
}

enum _ReconnectOutcome { success, failed, authCancelled }
