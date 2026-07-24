import 'dart:convert';
import 'dart:typed_data';

import 'package:helmhost/bridge.dart';

/// In-memory [IHelmBridge] for unit/integration tests (no native dylib).
class FakeHelmBridge implements IHelmBridge {
  FakeHelmBridge({
    this.width = 2,
    this.height = 2,
    Uint8List? rgba,
    List<Map<String, dynamic>>? registry,
    List<Map<String, dynamic>>? profiles,
  })  : rgba = rgba ?? Uint8List(width * height * 4),
        registry = registry ?? [],
        profiles = profiles ?? [];

  int width;
  int height;
  Uint8List rgba;
  final List<Map<String, dynamic>> registry;
  final List<Map<String, dynamic>> profiles;
  final List<Map<String, dynamic>> upserts = [];
  final List<int> closed = [];
  final List<int> grabbed = [];
  int fbCopyCalls = 0;
  final List<(int, int, int, int)> pointers = [];
  final List<(int, bool, int)> keys = [];
  final Map<int, List<Map<String, dynamic>>> _pollQueues = {};
  final Set<int> _alive = {};
  var _nextId = 1;
  var releaseFocusCount = 0;
  StateError? connectError;

  void enqueuePoll(int sessionId, Map<String, dynamic> event) {
    _pollQueues.putIfAbsent(sessionId, () => []).add(event);
  }

  @override
  String hello() => 'helmhost';

  @override
  String coreVersion() => '0.1.0';

  @override
  Future<void> initRegistry() async {}

  @override
  int connect(
    String host,
    int port, {
    String? username,
    String? password,
    bool preferVencrypt = false,
    bool acceptInvalidCerts = false,
    int bandwidthPreset = 1,
    int? qualityLevel,
    int? compressLevel,
  }) {
    if (connectError != null) throw connectError!;
    final id = _nextId++;
    _alive.add(id);
    return id;
  }

  @override
  Future<int> connectAsync(
    String host,
    int port, {
    String? username,
    String? password,
    bool preferVencrypt = false,
    bool acceptInvalidCerts = false,
    int bandwidthPreset = 1,
    int? qualityLevel,
    int? compressLevel,
  }) async {
    return connect(
      host,
      port,
      username: username,
      password: password,
      preferVencrypt: preferVencrypt,
      acceptInvalidCerts: acceptInvalidCerts,
      bandwidthPreset: bandwidthPreset,
      qualityLevel: qualityLevel,
      compressLevel: compressLevel,
    );
  }

  @override
  Map<String, dynamic> pollEvent(int sessionId) {
    final q = _pollQueues[sessionId];
    if (q == null || q.isEmpty) return {'type': 'none'};
    return q.removeAt(0);
  }

  @override
  (int, int) fbSize(int sessionId) {
    if (!_alive.contains(sessionId) && _alive.isNotEmpty) {
      // Allow fbSize for sessions that were connected; if never connected and
      // caller uses arbitrary id, still return size (hub live thumbs).
    }
    if (_alive.isNotEmpty && !_alive.contains(sessionId) && closed.contains(sessionId)) {
      throw StateError('unknown session');
    }
    return (width, height);
  }

  @override
  Uint8List fbCopy(int sessionId, int w, int h) {
    fbCopyCalls++;
    final need = w * h * 4;
    if (rgba.length < need) return Uint8List(need);
    return Uint8List.sublistView(rgba, 0, need);
  }

  @override
  void sendPointer(int sessionId, int x, int y, int buttons) {
    pointers.add((sessionId, x, y, buttons));
  }

  @override
  void sendKey(int sessionId, bool down, int keysym) {
    keys.add((sessionId, down, keysym));
  }

  @override
  void sendClipboard(int sessionId, String text) {}

  final List<(int, int, int)> desktopSizes = [];

  @override
  void requestDesktopSize(int sessionId, int width, int height) {
    desktopSizes.add((sessionId, width, height));
  }

  @override
  void close(int sessionId) {
    closed.add(sessionId);
    _alive.remove(sessionId);
  }

  @override
  void grab(int sessionId) => grabbed.add(sessionId);

  @override
  void releaseFocus() => releaseFocusCount++;

  @override
  List<dynamic> registryList() =>
      registry.map((e) => Map<String, dynamic>.from(e)).toList();

  @override
  void registryUpsertJson(Map<String, dynamic> entry) {
    upserts.add(Map<String, dynamic>.from(entry));
    final id = entry['id'];
    final i = registry.indexWhere((e) => e['id'] == id);
    if (i >= 0) {
      registry[i] = Map<String, dynamic>.from(entry);
    } else {
      registry.add(Map<String, dynamic>.from(entry));
    }
  }

  @override
  void registryRemove(String id) {
    registry.removeWhere((e) => e['id'] == id);
  }

  @override
  String registryExport() => jsonEncode({'connections': registry});

  @override
  void registryMergeJson(String json) {
    final decoded = jsonDecode(json);
    final list = decoded is Map
        ? (decoded['connections'] as List? ?? const [])
        : decoded as List;
    for (final raw in list) {
      registryUpsertJson(Map<String, dynamic>.from(raw as Map));
    }
  }

  @override
  Map<String, dynamic> registryResolve(String id) {
    for (final e in registry) {
      if (e['id'] == id) return Map<String, dynamic>.from(e);
    }
    throw StateError('missing $id');
  }

  @override
  List<dynamic> profileList() =>
      profiles.map((e) => Map<String, dynamic>.from(e)).toList();

  @override
  void profileUpsertJson(Map<String, dynamic> profile) {
    final id = profile['id'];
    final i = profiles.indexWhere((e) => e['id'] == id);
    if (i >= 0) {
      profiles[i] = Map<String, dynamic>.from(profile);
    } else {
      profiles.add(Map<String, dynamic>.from(profile));
    }
  }

  @override
  void profileRemove(String id) {
    profiles.removeWhere((e) => e['id'] == id);
  }
}
