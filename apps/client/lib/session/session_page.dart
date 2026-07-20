import 'dart:async';
import 'dart:ui' as ui;

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
import '../thumbs.dart';

class SessionPage extends StatefulWidget {
  const SessionPage({
    super.key,
    required this.sessionId,
    required this.title,
    this.entryId,
    this.closeOnExit = true,
    this.prefs,
    this.logger = const DebugPrintLogger(module: 'session'),
  });

  final int sessionId;
  final String title;
  final String? entryId;
  final bool closeOnExit;
  final AppPrefs? prefs;
  final ILogger logger;

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  late final HelmBridge _bridge;
  Timer? _pollTimer;
  ui.Image? _frame;
  int _fw = 0;
  int _fh = 0;
  bool _grabbed = true;
  bool _dirty = false;
  bool _pulling = false;
  bool _paintScheduled = false;
  String? _lastError;
  final _viewKey = GlobalKey();
  final _focusNode = FocusNode();
  final _downKeysyms = <int, int>{};
  late ViewScaleMode _scaleMode;
  Timer? _thumbTimer;
  Timer? _resizeDebounce;
  int _lastReqW = 0;
  int _lastReqH = 0;
  /// Stable pixel buffer for async image decode (not the bridge scratch).
  Uint8List? _decodeBuf;

  @override
  void initState() {
    super.initState();
    _scaleMode = widget.prefs?.viewScaleMode ?? ViewScaleMode.fit;
    _bridge = HelmBridge.open();
    _bridge.grab(widget.sessionId);
    // Poll protocol events; paint at most once per vsync when dirty.
    _pollTimer = Timer.periodic(const Duration(milliseconds: 8), (_) => _pollEvents());
    _thumbTimer = Timer.periodic(const Duration(seconds: 5), (_) => _captureThumb());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _thumbTimer?.cancel();
    _resizeDebounce?.cancel();
    _captureThumb();
    _releaseAllKeys();
    if (widget.closeOnExit) {
      try {
        _bridge.close(widget.sessionId);
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
        _bridge.sendKey(widget.sessionId, false, sym);
      } catch (_) {}
    }
    _downKeysyms.clear();
  }

  void _setGrabbed(bool grab) {
    if (grab) {
      _bridge.grab(widget.sessionId);
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
    // TigerVNC: rate-limit to ~100ms.
    _resizeDebounce = Timer(const Duration(milliseconds: 100), () {
      if (!mounted || !_scaleMode.usesRemoteResize) return;
      final box = _viewKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final w = box.size.width.round();
      final h = box.size.height.round();
      if (w <= 0 || h <= 0) return;
      if (w == _fw && h == _fh) return;
      try {
        _bridge.requestDesktopSize(widget.sessionId, w, h);
      } catch (e) {
        widget.logger.warn('requestDesktopSize failed', {'error': '$e'});
      }
    });
  }

  Future<void> _captureThumb() async {
    final id = widget.entryId ?? widget.title;
    await saveSessionThumb(_bridge, id, widget.sessionId);
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
      _bridge.sendClipboard(widget.sessionId, text);
    } catch (_) {}
  }

  void _markDirty() {
    _dirty = true;
    _schedulePaint();
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
    final (w, h) = _bridge.fbSize(widget.sessionId);
    if (w <= 0 || h <= 0) return;
    _fw = w;
    _fh = h;
    final pixels = _bridge.fbCopy(widget.sessionId, w, h);
    final len = pixels.length;
    if (_decodeBuf == null || _decodeBuf!.length != len) {
      _decodeBuf = Uint8List(len);
    }
    _decodeBuf!.setRange(0, len, pixels);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      _decodeBuf!,
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
    setState(() {
      _frame?.dispose();
      _frame = img;
      _lastError = null;
    });
    if (kDebugMode && sw.elapsedMilliseconds > 16) {
      widget.logger.debug('paint slow', {
        'w': w,
        'h': h,
        'ms': sw.elapsedMilliseconds,
      });
    }
  }

  void _pollEvents() {
    if (!mounted) return;
    try {
      for (var i = 0; i < 64; i++) {
        final ev = _bridge.pollEvent(widget.sessionId);
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
            'sessionId': widget.sessionId,
            'message': msg,
          });
          if (mounted) {
            setState(() => _lastError = msg);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg)),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _lastError = e.toString());
      }
    }
  }

  (int, int)? _remoteXY(Offset global) {
    final box = _viewKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || _fw <= 0 || _fh <= 0) return null;
    final local = box.globalToLocal(global);
    final vw = box.size.width;
    final vh = box.size.height;
    if (vw <= 0 || vh <= 0) return null;

    // Always aspect-preserving (never stretch). When RemoteResize matched
    // FB to the view, scale≈1 and offsets≈0.
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
    if (!_grabbed) return;
    _lastPointerGlobal = global;
    _focusNode.requestFocus();
    final xy = _remoteXY(global);
    if (xy == null) return;
    try {
      _bridge.sendPointer(widget.sessionId, xy.$1, xy.$2, buttons);
    } catch (_) {}
  }

  /// Convert accumulated scroll/pan into RFB wheel button clicks (4–7).
  void _flushWheel(Offset global) {
    const step = 20.0;
    // Emit discrete press+release clicks (TigerVNC). Prefer last known
    // pointer if the event position maps outside the FB (letterbox).
    void click(int mask) {
      final pos = _remoteXY(global) != null
          ? global
          : (_lastPointerGlobal ?? global);
      _onPointer(pos, mask);
      _onPointer(pos, 0);
    }

    while (_scrollAccY <= -step) {
      click(1 << 3); // button 4 — up
      _scrollAccY += step;
    }
    while (_scrollAccY >= step) {
      click(1 << 4); // button 5 — down
      _scrollAccY -= step;
    }
    while (_scrollAccX <= -step) {
      click(1 << 5); // button 6 — left
      _scrollAccX += step;
    }
    while (_scrollAccX >= step) {
      click(1 << 6); // button 7 — right
      _scrollAccX -= step;
    }
  }

  /// Mouse wheel (PointerScrollEvent) still used on some platforms.
  void _onScroll(PointerScrollEvent e) {
    if (!_grabbed) return;
    _scrollAccX -= e.scrollDelta.dx;
    _scrollAccY -= e.scrollDelta.dy;
    _flushWheel(e.position);
  }

  /// macOS / desktop trackpad two-finger scroll arrives as PanZoom, not Scroll.
  void _onPanZoomUpdate(PointerPanZoomUpdateEvent e) {
    if (!_grabbed) return;
    _scrollAccX -= e.panDelta.dx;
    _scrollAccY -= e.panDelta.dy;
    _flushWheel(e.position);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_grabbed) return KeyEventResult.ignored;

    final phys = event.physicalKey.usbHidUsage;
    final down = event is KeyDownEvent || event is KeyRepeatEvent;

    if (!down) {
      final sym = _downKeysyms.remove(phys);
      if (sym == null) return KeyEventResult.ignored;
      try {
        _bridge.sendKey(widget.sessionId, false, sym);
      } catch (_) {}
      return KeyEventResult.handled;
    }

    if (event is KeyRepeatEvent) {
      final sym = _downKeysyms[phys];
      if (sym == null) return KeyEventResult.ignored;
      try {
        _bridge.sendKey(widget.sessionId, true, sym);
      } catch (_) {}
      return KeyEventResult.handled;
    }

    final sym = keysymForKeyEvent(event);
    if (sym == null) return KeyEventResult.ignored;
    _downKeysyms[phys] = sym;
    try {
      _bridge.sendKey(widget.sessionId, true, sym);
    } catch (_) {}
    return KeyEventResult.handled;
  }

  Widget _frameChild() {
    if (_frame == null) {
      return Center(
        child: Text(
          _lastError ?? 'Waiting for framebuffer…',
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }
    final image = RawImage(
      image: _frame,
      width: _fw.toDouble(),
      height: _fh.toDouble(),
      fit: BoxFit.fill,
      filterQuality: FilterQuality.low,
    );
    // Never stretch the desktop: contain only. Fill window = RemoteResize so
    // FB eventually matches the view (1:1, no letterbox).
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: _fw.toDouble(),
          height: _fh.toDouble(),
          child: image,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true): _pasteToRemote,
        const SingleActivator(LogicalKeyboardKey.keyV, control: true):
            _pasteToRemote,
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
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
            if (_lastError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Center(
                  child: Text(
                    _lastError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
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
          // Hide Mac pointer while grabbed; remote soft-cursor stays in FB pixels.
          child: MouseRegion(
            cursor: _grabbed
                ? SystemMouseCursors.none
                : SystemMouseCursors.basic,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerHover: (e) => _onPointer(e.position, 0),
              onPointerDown: (e) =>
                  _onPointer(e.position, e.buttons == 0 ? 1 : e.buttons),
              onPointerMove: (e) => _onPointer(e.position, e.buttons),
              onPointerUp: (e) => _onPointer(e.position, 0),
              onPointerSignal: (e) {
                if (e is PointerScrollEvent) _onScroll(e);
              },
              onPointerPanZoomUpdate: _onPanZoomUpdate,
              child: ColoredBox(
                key: _viewKey,
                color: Colors.black,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _onViewSize(Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    ));
                    return _frameChild();
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
