import 'dart:async';
import 'dart:ui' as ui;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../bridge.dart';
import '../keysyms.dart';
import '../logging/logger.dart';
import '../prefs.dart';
import '../session_helpers.dart';
import '../storage/credential_store.dart';
import '../thumbs.dart';
import 'buffering_overlay.dart';
import 'fb_texture.dart';
import 'session_ipc.dart';
import 'session_link_stats.dart';

class SessionPage extends StatefulWidget {
  SessionPage({
    super.key,
    required this.sessionId,
    required this.title,
    required this.host,
    required this.port,
    this.entryId,
    this.username,
    this.preferVencrypt = false,
    this.acceptInvalidCerts = false,
    this.closeOnExit = true,
    this.prefs,
    ILogger? logger,
  }) : logger = logger ?? defaultLogger(module: 'session');

  final int sessionId;
  final String title;
  final String host;
  final int port;
  final String? entryId;
  final String? username;
  final bool preferVencrypt;
  final bool acceptInvalidCerts;
  final bool closeOnExit;
  final AppPrefs? prefs;
  final ILogger logger;

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
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
  bool _hubNotifiedEnd = false;
  bool _reconnectDialogShowing = false;
  String? _lastError;
  SessionConnState _connState = SessionConnState.connecting;
  int _reconnectAttempt = 0;
  final _linkStats = SessionLinkStats();
  final _viewKey = GlobalKey();
  final _focusNode = FocusNode();
  final _downKeysyms = <int, int>{};
  late ViewScaleMode _scaleMode;
  Timer? _thumbTimer;
  Timer? _resizeDebounce;
  int _lastReqW = 0;
  int _lastReqH = 0;
  static final bool _paintTrace =
      const bool.fromEnvironment('HELMHOST_PAINT_TRACE', defaultValue: false);

  @override
  void initState() {
    super.initState();
    _sessionId = widget.sessionId;
    _scaleMode = widget.prefs?.viewScaleMode ?? ViewScaleMode.fit;
    _bridge = HelmBridge.open();
    _bridge.grab(_sessionId);
    _pollTimer =
        Timer.periodic(const Duration(milliseconds: 8), (_) => _pollEvents());
    _thumbTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _captureThumb());
    _statsUiTimer =
        Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _connState == SessionConnState.live) setState(() {});
    });
    _armFirstFrameTimeout();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
    unawaited(_initTexture());
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
    final tex = await FbTextureController.create();
    if (!mounted || tex == null) return;
    setState(() {
      _fbTex = tex;
      _textureId = tex.textureId;
    });
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

  @override
  void dispose() {
    _pollTimer?.cancel();
    _thumbTimer?.cancel();
    _resizeDebounce?.cancel();
    _firstFrameTimer?.cancel();
    _statsUiTimer?.cancel();
    _captureThumb();
    unawaited(_notifyHubEnded(reason: 'window_closed'));
    unawaited(_fbTex?.dispose() ?? Future<void>.value());
    _fbTex = null;
    _releaseAllKeys();
    if (widget.closeOnExit) {
      try {
        _bridge.close(_sessionId);
      } catch (_) {}
    }
    try {
      _bridge.releaseFocus();
    } catch (_) {}
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
  }

  void _setGrabbed(bool grab) {
    if (grab) {
      _bridge.grab(_sessionId);
      _focusNode.requestFocus();
    } else {
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

  void _markDirty() {
    _linkStats.recordFrame();
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

    final tex = _fbTex;
    if (tex != null) {
      final presented = await tex.present(_sessionId);
      if (!mounted) return;
      if (presented) {
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
          });
        }
        return;
      }
      // Soft fail / skipped — fall through to Dart decode path.
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
    if (!mounted) return;
    if (_connState == SessionConnState.timedOut ||
        _connState == SessionConnState.disconnected) {
      // Still drain queue so we don't backlog, but ignore for UI.
    }
    try {
      for (var i = 0; i < 64; i++) {
        final ev = _bridge.pollEvent(_sessionId);
        final type = ev['type'] as String? ?? 'none';
        if (type == 'none') break;
        if (type == 'desktop_resize') {
          _fw = (ev['w'] as num).toInt();
          _fh = (ev['h'] as num).toInt();
          _markDirty();
        } else if (type == 'framebuffer_dirty') {
          _markDirty();
        } else if (type == 'bell') {
          _onBell();
        } else if (type == 'clipboard') {
          unawaited(_onClipboard(ev['text'] as String? ?? ''));
        } else if (type == 'disconnected' || type == 'error') {
          final msg = type == 'error'
              ? (ev['message'] as String? ?? ev.toString())
              : 'Disconnected';
          widget.logger.warn(type, {
            'sessionId': _sessionId,
            'message': msg,
          });
          unawaited(_handleDisconnect(msg));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _lastError = e.toString());
      }
    }
  }

  Future<void> _handleDisconnect(String msg) async {
    if (_connState == SessionConnState.reconnecting) return;
    await _notifyHubEnded(reason: msg);
    if (!mounted) return;
    setState(() {
      _connState = SessionConnState.disconnected;
      _lastError = msg;
    });
    await _showReconnectDialog(reason: msg);
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
      await windowCloseSelf();
    }
  }

  Future<void> windowCloseSelf() async {
    try {
      final c = await WindowController.fromCurrentEngine();
      await c.invokeMethod(kMethodWindowClose);
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> _runReconnectLoop() async {
    setState(() {
      _connState = SessionConnState.reconnecting;
      _reconnectAttempt = 0;
      _lastError = null;
      _fw = 0;
      _fh = 0;
      _frame?.dispose();
      _frame = null;
      _linkStats.reset();
    });

    for (var i = 0; i < _maxReconnectAttempts; i++) {
      if (!mounted) return;
      setState(() => _reconnectAttempt = i + 1);
      if (i > 0) {
        await Future<void>.delayed(_backoff[i - 1]);
      }
      final ok = await _attemptReconnect();
      if (ok) return;
    }

    if (!mounted) return;
    setState(() {
      _connState = SessionConnState.disconnected;
      _lastError = 'Reconnect failed after $_maxReconnectAttempts attempts';
    });
    await _showReconnectDialog(reason: _lastError!);
  }

  Future<bool> _attemptReconnect() async {
    final oldId = _sessionId;
    await _notifyHubEnded(reason: 'reconnect');
    try {
      _bridge.close(oldId);
    } catch (_) {}

    String? password;
    final entryId = widget.entryId ?? sessionKey(widget.host, widget.port);
    try {
      password = await createCredentialStore().readPassword(entryId);
    } catch (_) {}

    try {
      final newId = _bridge.connect(
        widget.host,
        widget.port,
        username: widget.username,
        password: password,
        preferVencrypt: widget.preferVencrypt,
        acceptInvalidCerts: widget.acceptInvalidCerts,
      );
      _bridge.grab(newId);
      await _notifyHubReplaced(oldId, newId);
      if (!mounted) return false;
      setState(() {
        _sessionId = newId;
        _hubNotifiedEnd = false;
        _connState = SessionConnState.connecting;
        _lastError = null;
      });
      _armFirstFrameTimeout();

      // Wait up to reconnect timeout for first frame.
      final deadline = DateTime.now().add(_reconnectTimeout);
      while (mounted && DateTime.now().isBefore(deadline)) {
        if (_hasFramebuffer || _connState == SessionConnState.live) {
          return true;
        }
        if (_connState == SessionConnState.disconnected) return false;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return _hasFramebuffer || _connState == SessionConnState.live;
    } catch (e) {
      widget.logger.error('reconnect failed', {'error': '$e'});
      if (mounted) {
        setState(() => _lastError = e.toString());
      }
      return false;
    }
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
    try {
      _bridge.sendPointer(_sessionId, xy.$1, xy.$2, buttons);
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
      final sym = _downKeysyms.remove(phys);
      if (sym == null) return KeyEventResult.ignored;
      try {
        _bridge.sendKey(_sessionId, false, sym);
      } catch (_) {}
      return KeyEventResult.handled;
    }

    if (event is KeyRepeatEvent) {
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

  Widget _linkChip() {
    final hz = _linkStats.hz();
    final stale = _linkStats.isStale();
    final Color color = switch (_connState) {
      SessionConnState.live => stale ? Colors.amber : Colors.greenAccent,
      SessionConnState.connecting || SessionConnState.reconnecting =>
        Colors.lightBlueAccent,
      SessionConnState.timedOut || SessionConnState.disconnected =>
        Colors.redAccent,
    };
    final rate = _connState == SessionConnState.live
        ? ' · ~${hz.toStringAsFixed(0)} Hz${stale ? ' · stale' : ''}'
        : '';
    return Tooltip(
      message: 'Frame update rate (not network Mbps)',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Center(
          child: Text(
            '${_connState.label}$rate',
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
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
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
            _pasteToRemote,
        const SingleActivator(LogicalKeyboardKey.keyV, control: true):
            _pasteToRemote,
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            _linkChip(),
            IconButton(
              tooltip: 'Paste clipboard to remote',
              onPressed: _pasteToRemote,
              icon: const Icon(Icons.content_paste),
            ),
            PopupMenuButton<ViewScaleMode>(
              tooltip:
                  'Fit = letterbox locally. Fill window = resize remote desktop (no stretch).',
              initialValue: _scaleMode,
              onSelected: _setScaleMode,
              itemBuilder: (context) => [
                for (final m in ViewScaleMode.values)
                  CheckedPopupMenuItem(
                    value: m,
                    checked: m == _scaleMode,
                    child: Text(m.label),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    const Icon(Icons.aspect_ratio, size: 18),
                    const SizedBox(width: 4),
                    Text(_scaleMode.label),
                    const Icon(Icons.arrow_drop_down, size: 20),
                  ],
                ),
              ),
            ),
            if (_lastError != null && _connState != SessionConnState.live)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Center(
                  child: Text(
                    _connState.label,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            TextButton(
              onPressed: () => _setGrabbed(!_grabbed),
              child: Text(_grabbed ? 'Release input' : 'Grab input'),
            ),
          ],
        ),
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
        bottomNavigationBar: _lastError == null
            ? null
            : Material(
                color: Theme.of(context).colorScheme.errorContainer,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(_lastError!),
                  ),
                ),
              ),
      ),
    );
  }
}
