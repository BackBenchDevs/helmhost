import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'bridge.dart';
import 'keysyms.dart';
import 'session_helpers.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final controller = await WindowController.fromCurrentEngine();
  final raw = controller.arguments.trim();
  Map<String, dynamic> winArgs = {};
  if (raw.isNotEmpty) {
    try {
      winArgs = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      winArgs = {};
    }
  }

  await controller.setWindowMethodHandler((call) async {
    switch (call.method) {
      case 'window_close':
        await windowManager.close();
        return null;
      default:
        throw MissingPluginException(call.method);
    }
  });

  final role = winArgs['role'] as String? ?? 'hub';
  if (role == 'session') {
    final sessionId = (winArgs['sessionId'] as num).toInt();
    final title = winArgs['title'] as String? ?? 'Session';
    await windowManager.setTitle(title);
    runApp(SessionApp(sessionId: sessionId, title: title));
  } else {
    await windowManager.setTitle('Helmhost');
    runApp(const HubApp());
  }
}

extension on WindowController {
  Future<void> closeWindow() => invokeMethod('window_close');
}

class HubApp extends StatelessWidget {
  const HubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Helmhost',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B4D3E)),
        useMaterial3: true,
      ),
      home: const HubPage(),
    );
  }
}

class SessionApp extends StatelessWidget {
  const SessionApp({super.key, required this.sessionId, required this.title});

  final int sessionId;
  final String title;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: title,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B4D3E)),
        useMaterial3: true,
      ),
      home: SessionPage(
        sessionId: sessionId,
        title: title,
        closeOnExit: true,
      ),
    );
  }
}

class HubPage extends StatefulWidget {
  const HubPage({super.key});

  @override
  State<HubPage> createState() => _HubPageState();
}

class _HubPageState extends State<HubPage> with WindowListener {
  HelmBridge? _bridge;
  String _hello = '';
  String? _error;
  List<dynamic> _entries = [];
  final _host = TextEditingController(text: '127.0.0.1');
  final _port = TextEditingController(text: '5900');
  final _password = TextEditingController();
  final _sessions = <_OpenSession>[];
  bool _connecting = false;

  List<OpenSessionRef> get _sessionRefs => _sessions
      .map((s) => OpenSessionRef(id: s.id, host: s.host, port: s.port))
      .toList();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
    _boot();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _host.dispose();
    _port.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() async {
    for (final s in List<_OpenSession>.from(_sessions)) {
      try {
        _bridge?.close(s.id);
      } catch (_) {}
      try {
        final all = await WindowController.getAll();
        for (final c in all) {
          if (c.arguments.isEmpty) continue;
          final a = jsonDecode(c.arguments) as Map<String, dynamic>;
          if (a['role'] == 'session' &&
              (a['sessionId'] as num).toInt() == s.id) {
            await c.closeWindow();
          }
        }
      } catch (_) {}
    }
    await windowManager.destroy();
  }

  Future<void> _boot() async {
    try {
      final b = HelmBridge.open();
      await b.initRegistry();
      setState(() {
        _bridge = b;
        _hello = b.hello();
        _entries = b.registryList();
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _openSessionWindow(int id, String title) async {
    final args = jsonEncode({
      'role': 'session',
      'sessionId': id,
      'title': title,
    });
    final existing = await WindowController.getAll();
    for (final c in existing) {
      if (c.arguments.isEmpty) continue;
      try {
        final a = jsonDecode(c.arguments) as Map<String, dynamic>;
        if (a['role'] != 'session') continue;
        final sid = (a['sessionId'] as num?)?.toInt();
        final t = a['title'] as String?;
        if (sid == id || t == title) {
          await c.show();
          return;
        }
      } catch (_) {}
    }
    final created = await WindowController.create(
      WindowConfiguration(arguments: args, hiddenAtLaunch: true),
    );
    await created.show();
  }

  Future<void> _connect() async {
    final b = _bridge;
    if (b == null || _connecting) return;
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? 5900;
    final pw = _password.text;

    final existing = findOpenByHostPort(_sessionRefs, host, port);
    if (existing != null) {
      b.grab(existing.id);
      await _openSessionWindow(existing.id, sessionKey(host, port));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session already open')),
      );
      return;
    }

    setState(() => _connecting = true);
    try {
      final id = b.connect(host, port, pw.isEmpty ? null : pw);
      b.grab(id);
      b.registryUpsert(sessionKey(host, port), host, port, null);
      final title = sessionKey(host, port);
      setState(() {
        _sessions.add(_OpenSession(id: id, host: host, port: port));
        _entries = b.registryList();
      });
      await _openSessionWindow(id, title);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connect failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _openSaved(Map<String, dynamic> e) async {
    _host.text = e['host'] as String? ?? '';
    _port.text = '${e['port'] ?? 5900}';
    await _connect();
  }

  Future<void> _openSession(_OpenSession s) async {
    _bridge?.grab(s.id);
    await _openSessionWindow(s.id, s.title);
  }

  Future<void> _disconnectSession(_OpenSession s) async {
    try {
      _bridge?.close(s.id);
    } catch (_) {}
    final all = await WindowController.getAll();
    for (final c in all) {
      if (c.arguments.isEmpty) continue;
      try {
        final a = jsonDecode(c.arguments) as Map<String, dynamic>;
        if (a['role'] == 'session' &&
            (a['sessionId'] as num).toInt() == s.id) {
          await c.closeWindow();
        }
      } catch (_) {}
    }
    setState(() => _sessions.removeWhere((x) => x.id == s.id));
  }

  Widget _savedList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Saved connections',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_entries.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('No saved connections yet'),
          )
        else
          ..._entries.map((raw) {
            final e = raw as Map<String, dynamic>;
            final title =
                e['display_name'] as String? ?? '${e['host']}:${e['port']}';
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(title),
              subtitle: Text('${e['host']}:${e['port']}'),
              onTap: () => _openSaved(e),
            );
          }),
      ],
    );
  }

  Widget _connectForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Connect', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(
          controller: _host,
          decoration: const InputDecoration(
            labelText: 'Host',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _port,
          decoration: const InputDecoration(
            labelText: 'Port',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: (_bridge == null || _connecting) ? null : _connect,
          child: Text(_connecting ? 'Connecting…' : 'Connect'),
        ),
        if (_sessions.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Open sessions',
              style: Theme.of(context).textTheme.titleMedium),
          ..._sessions.map(
            (s) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.title),
              subtitle: Text('id ${s.id}'),
              onTap: () => _openSession(s),
              trailing: IconButton(
                tooltip: 'Disconnect',
                icon: const Icon(Icons.close),
                onPressed: () => _disconnectSession(s),
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          final body = wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 280,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: _savedList(),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: _connectForm(),
                      ),
                    ),
                  ],
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _connectForm(),
                      const SizedBox(height: 24),
                      _savedList(),
                    ],
                  ),
                );
          return Column(
            children: [
              if (_error != null)
                ColoredBox(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ListTile(
                    dense: true,
                    title: Text(_error!, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: TextButton(onPressed: _boot, child: const Text('Retry')),
                  ),
                ),
              Expanded(child: body),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  _error != null ? 'Bridge error' : 'Helmhost · $_hello',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OpenSession {
  _OpenSession({required this.id, required this.host, required this.port});
  final int id;
  final String host;
  final int port;
  String get title => sessionKey(host, port);
}

class SessionPage extends StatefulWidget {
  const SessionPage({
    super.key,
    required this.sessionId,
    required this.title,
    this.closeOnExit = true,
  });

  final int sessionId;
  final String title;
  final bool closeOnExit;

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  late final HelmBridge _bridge;
  Timer? _timer;
  ui.Image? _frame;
  int _fw = 0;
  int _fh = 0;
  bool _grabbed = true;
  bool _dirty = false;
  bool _pumping = false;
  String? _lastError;
  final _viewKey = GlobalKey();
  final _focusNode = FocusNode();
  /// physicalKey.usbHidUsage → keysym sent on press (matched on release).
  final _downKeysyms = <int, int>{};
  ViewScaleMode _scaleMode = ViewScaleMode.fit;

  @override
  void initState() {
    super.initState();
    _bridge = HelmBridge.open();
    _bridge.grab(widget.sessionId);
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) => _pump());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
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

  Future<void> _pullFramebuffer() async {
    final (w, h) = _bridge.fbSize(widget.sessionId);
    if (w <= 0 || h <= 0) return;
    _fw = w;
    _fh = h;
    final pixels = _bridge.fbCopy(widget.sessionId, w, h);
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
    setState(() {
      _frame?.dispose();
      _frame = img;
      _lastError = null;
    });
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      var dirty = _dirty;
      _dirty = false;
      for (var i = 0; i < 64; i++) {
        final ev = _bridge.pollEvent(widget.sessionId);
        final type = ev['type'] as String? ?? 'none';
        if (type == 'none') break;
        if (type == 'desktop_resize') {
          _fw = (ev['w'] as num).toInt();
          _fh = (ev['h'] as num).toInt();
          dirty = true;
        } else if (type == 'framebuffer_dirty') {
          dirty = true;
        } else if (type == 'disconnected' || type == 'error') {
          final msg = type == 'error'
              ? (ev['message'] as String? ?? ev.toString())
              : 'Disconnected';
          if (mounted) {
            setState(() => _lastError = msg);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg)),
            );
          }
        }
      }
      if (dirty) {
        await _pullFramebuffer();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _lastError = e.toString());
      }
    } finally {
      _pumping = false;
    }
  }

  /// Map pointer into remote FB coords for current scale mode.
  (int, int)? _remoteXY(Offset global) {
    final box = _viewKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || _fw <= 0 || _fh <= 0) return null;
    final local = box.globalToLocal(global);
    final vw = box.size.width;
    final vh = box.size.height;
    if (vw <= 0 || vh <= 0) return null;

    if (_scaleMode == ViewScaleMode.oneToOne) {
      final rx = local.dx.round();
      final ry = local.dy.round();
      if (rx < 0 || ry < 0 || rx >= _fw || ry >= _fh) return null;
      return (rx, ry);
    }

    final fit = _scaleMode.boxFit ?? BoxFit.contain;
    late final double scale;
    late final double ox;
    late final double oy;
    if (fit == BoxFit.cover) {
      scale = (vw / _fw > vh / _fh) ? vw / _fw : vh / _fh;
      final dw = _fw * scale;
      final dh = _fh * scale;
      ox = (vw - dw) / 2;
      oy = (vh - dh) / 2;
    } else {
      scale = (vw / _fw < vh / _fh) ? vw / _fw : vh / _fh;
      final dw = _fw * scale;
      final dh = _fh * scale;
      ox = (vw - dw) / 2;
      oy = (vh - dh) / 2;
    }
    final rx = ((local.dx - ox) / scale).round();
    final ry = ((local.dy - oy) / scale).round();
    if (rx < 0 || ry < 0 || rx >= _fw || ry >= _fh) return null;
    return (rx, ry);
  }

  void _onPointer(Offset global, int buttons) {
    if (!_grabbed) return;
    _focusNode.requestFocus();
    final xy = _remoteXY(global);
    if (xy == null) return;
    try {
      _bridge.sendPointer(widget.sessionId, xy.$1, xy.$2, buttons);
    } catch (_) {}
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

    // KeyRepeat: re-send down with same keysym if already tracked
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
    );
    final fit = _scaleMode.boxFit;
    if (fit == null) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: SizedBox(
            width: _fw.toDouble(),
            height: _fh.toDouble(),
            child: image,
          ),
        ),
      );
    }
    return SizedBox.expand(
      child: FittedBox(
        fit: fit,
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          PopupMenuButton<ViewScaleMode>(
            tooltip: 'View scale (local only; remote size is shared)',
            initialValue: _scaleMode,
            onSelected: (m) => setState(() => _scaleMode = m),
            itemBuilder: (context) => [
              for (final m in ViewScaleMode.values)
                CheckedPopupMenuItem(
                  value: m,
                  checked: m == _scaleMode,
                  child: Text(m.label),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.aspect_ratio, size: 18),
                  const SizedBox(width: 4),
                  Text(_scaleMode.label),
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
                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
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
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerHover: (e) => _onPointer(e.position, 0),
          onPointerDown: (e) =>
              _onPointer(e.position, e.buttons == 0 ? 1 : e.buttons),
          onPointerMove: (e) => _onPointer(e.position, e.buttons),
          onPointerUp: (e) => _onPointer(e.position, 0),
          child: ColoredBox(
            key: _viewKey,
            color: Colors.black,
            child: _frameChild(),
          ),
        ),
      ),
    );
  }
}
