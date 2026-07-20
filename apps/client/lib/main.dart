import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bridge.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HelmhostApp());
}

class HelmhostApp extends StatelessWidget {
  const HelmhostApp({super.key});

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

class HubPage extends StatefulWidget {
  const HubPage({super.key});

  @override
  State<HubPage> createState() => _HubPageState();
}

class _HubPageState extends State<HubPage> {
  HelmBridge? _bridge;
  String _hello = '';
  String? _error;
  List<dynamic> _entries = [];
  final _host = TextEditingController(text: '127.0.0.1');
  final _port = TextEditingController(text: '5900');
  final _password = TextEditingController();
  final _sessions = <_OpenSession>[];

  @override
  void initState() {
    super.initState();
    _boot();
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

  Future<void> _connect() async {
    final b = _bridge;
    if (b == null) return;
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? 5900;
    final pw = _password.text;
    try {
      final id = b.connect(host, port, pw.isEmpty ? null : pw);
      b.grab(id);
      b.registryUpsert('$host:$port', host, port, null);
      setState(() {
        _sessions.add(_OpenSession(id: id, title: '$host:$port'));
        _entries = b.registryList();
      });
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SessionPage(
            bridge: b,
            sessionId: id,
            title: '$host:$port',
            closeOnExit: false,
            onClosed: () {},
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connect failed: $e')),
      );
    }
  }

  Future<void> _openSaved(Map<String, dynamic> e) async {
    _host.text = e['host'] as String? ?? '';
    _port.text = '${e['port'] ?? 5900}';
    await _connect();
  }

  Future<void> _openSession(_OpenSession s) async {
    final b = _bridge;
    if (b == null) return;
    b.grab(s.id);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SessionPage(
          bridge: b,
          sessionId: s.id,
          title: s.title,
          closeOnExit: false,
          onClosed: () {},
        ),
      ),
    );
  }

  Future<void> _disconnectSession(_OpenSession s) async {
    try {
      _bridge?.close(s.id);
    } catch (_) {}
    setState(() => _sessions.removeWhere((x) => x.id == s.id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Helmhost')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Hub',
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    _error != null
                        ? 'Bridge: $_error'
                        : 'FFI hello: $_hello · focus: ${_bridge?.focusGet() ?? "-"}',
                  ),
                  const SizedBox(height: 24),
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
                    onPressed: _bridge == null ? null : _connect,
                    child: const Text('Connect'),
                  ),
                  const SizedBox(height: 24),
                  Text('Saved connections',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_entries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('No saved connections yet')),
                    )
                  else
                    ..._entries.map((raw) {
                      final e = raw as Map<String, dynamic>;
                      final title = e['display_name'] as String? ??
                          '${e['host']}:${e['port']}';
                      return ListTile(
                        title: Text(title),
                        subtitle: Text('${e['host']}:${e['port']}'),
                        onTap: () => _openSaved(e),
                      );
                    }),
                  if (_sessions.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Open sessions',
                        style: Theme.of(context).textTheme.titleMedium),
                    ..._sessions.map(
                      (s) => ListTile(
                        title: Text(s.title),
                        subtitle: Text('id ${s.id}'),
                        onTap: () => _openSession(s),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => _disconnectSession(s),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OpenSession {
  _OpenSession({required this.id, required this.title});
  final int id;
  final String title;
}

class SessionPage extends StatefulWidget {
  const SessionPage({
    super.key,
    required this.bridge,
    required this.sessionId,
    required this.title,
    required this.onClosed,
    this.closeOnExit = true,
  });

  final HelmBridge bridge;
  final int sessionId;
  final String title;
  final VoidCallback onClosed;
  final bool closeOnExit;

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  Timer? _timer;
  ui.Image? _frame;
  int _fw = 0;
  int _fh = 0;
  Uint8List? _fb;
  bool _grabbed = true;

  @override
  void initState() {
    super.initState();
    widget.bridge.grab(widget.sessionId);
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) => _pump());
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (widget.closeOnExit) {
      try {
        widget.bridge.close(widget.sessionId);
      } catch (_) {}
      widget.onClosed();
    }
    widget.bridge.releaseFocus();
    _frame?.dispose();
    super.dispose();
  }

  Future<void> _pump() async {
    try {
      for (var i = 0; i < 32; i++) {
        final ev = widget.bridge.pollEvent(widget.sessionId);
        final type = ev['type'] as String? ?? 'none';
        if (type == 'none') break;
        if (type == 'desktop_resize') {
          _fw = ev['w'] as int;
          _fh = ev['h'] as int;
          _fb = Uint8List(_fw * _fh * 4);
        } else if (type == 'damage') {
          await _applyDamage(ev);
        } else if (type == 'disconnected' || type == 'error') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(ev.toString())),
            );
          }
        }
      }
    } catch (e) {
      // ignore transient
    }
  }

  Future<void> _applyDamage(Map<String, dynamic> ev) async {
    final x = ev['x'] as int;
    final y = ev['y'] as int;
    final w = ev['w'] as int;
    final h = ev['h'] as int;
    final b64 = ev['rgba_b64'] as String;
    final rgba = base64Decode(b64);
    if (_fb == null || _fw == 0 || _fh == 0) {
      _fw = x + w;
      _fh = y + h;
      _fb = Uint8List(_fw * _fh * 4);
    }
    final fb = _fb!;
    for (var row = 0; row < h; row++) {
      final src = row * w * 4;
      final dst = ((y + row) * _fw + x) * 4;
      if (dst + w * 4 <= fb.length && src + w * 4 <= rgba.length) {
        fb.setRange(dst, dst + w * 4, rgba, src);
      }
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      Uint8List.fromList(fb),
      _fw,
      _fh,
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
    });
  }

  void _onPointer(PointerEvent e, int buttons) {
    if (!_grabbed) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || _fw == 0) return;
    final local = box.globalToLocal(e.position);
    final scaleX = _fw / box.size.width;
    final scaleY = _fh / box.size.height;
    final x = (local.dx * scaleX).round().clamp(0, _fw - 1);
    final y = (local.dy * scaleY).round().clamp(0, _fh - 1);
    widget.bridge.sendPointer(widget.sessionId, x, y, buttons);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_grabbed) return KeyEventResult.ignored;
    // Minimal ASCII / return mapping for MVP
    final key = event.logicalKey;
    var keysym = 0;
    if (key == LogicalKeyboardKey.enter) {
      keysym = 0xff0d;
    } else if (key == LogicalKeyboardKey.backspace) {
      keysym = 0xff08;
    } else if (key == LogicalKeyboardKey.escape) {
      keysym = 0xff1b;
      widget.bridge.releaseFocus();
      setState(() => _grabbed = false);
      return KeyEventResult.handled;
    } else if (key.keyLabel.length == 1) {
      keysym = key.keyLabel.codeUnitAt(0);
    }
    if (keysym != 0) {
      widget.bridge.sendKey(
        widget.sessionId,
        event is KeyDownEvent || event is KeyRepeatEvent,
        keysym,
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: () {
              if (_grabbed) {
                widget.bridge.releaseFocus();
              } else {
                widget.bridge.grab(widget.sessionId);
              }
              setState(() => _grabbed = !_grabbed);
            },
            child: Text(_grabbed ? 'Release input' : 'Grab input'),
          ),
        ],
      ),
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Listener(
          onPointerDown: (e) => _onPointer(e, 1),
          onPointerMove: (e) => _onPointer(e, e.buttons),
          onPointerUp: (e) => _onPointer(e, 0),
          child: ColoredBox(
            color: Colors.black,
            child: Center(
              child: _frame == null
                  ? const Text('Waiting for framebuffer…',
                      style: TextStyle(color: Colors.white70))
                  : RawImage(image: _frame, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }
}
