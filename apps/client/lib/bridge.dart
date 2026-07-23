import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'storage/app_paths.dart';

/// Session/registry surface used by UI (testable without native dylib).
abstract class IHelmBridge {
  String hello();
  /// Rust workspace / FFI crate version (`CARGO_PKG_VERSION`).
  String coreVersion();
  Future<void> initRegistry();

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
  });

  Map<String, dynamic> pollEvent(int sessionId);
  (int, int) fbSize(int sessionId);
  Uint8List fbCopy(int sessionId, int width, int height);
  void sendPointer(int sessionId, int x, int y, int buttons);
  void sendKey(int sessionId, bool down, int keysym);
  void sendClipboard(int sessionId, String text);
  void requestDesktopSize(int sessionId, int width, int height);
  void close(int sessionId);
  void grab(int sessionId);
  void releaseFocus();

  List<dynamic> registryList();
  void registryUpsertJson(Map<String, dynamic> entry);
  void registryRemove(String id);
  String registryExport();
  void registryMergeJson(String json);
  Map<String, dynamic> registryResolve(String id);
  List<dynamic> profileList();
  void profileUpsertJson(Map<String, dynamic> profile);
  void profileRemove(String id);
}

typedef _HelloNative = Pointer<Utf8> Function();
typedef _HelloDart = Pointer<Utf8> Function();
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _FreeDart = void Function(Pointer<Utf8>);
typedef _ConnectNative = Pointer<Utf8> Function(
    Pointer<Utf8>,
    Uint16,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Uint8,
    Uint8,
    Uint8,
    Int8,
    Int8);
typedef _ConnectDart = Pointer<Utf8> Function(
    Pointer<Utf8>, int, Pointer<Utf8>, Pointer<Utf8>, int, int, int, int, int);
typedef _PollNative = Pointer<Utf8> Function(Uint64);
typedef _PollDart = Pointer<Utf8> Function(int);
typedef _PtrNative = Int32 Function(Uint64, Int32, Int32, Uint8);
typedef _PtrDart = int Function(int, int, int, int);
typedef _KeyNative = Int32 Function(Uint64, Uint8, Uint32);
typedef _KeyDart = int Function(int, int, int);
typedef _ClipNative = Pointer<Utf8> Function(Uint64, Pointer<Utf8>);
typedef _ClipDart = Pointer<Utf8> Function(int, Pointer<Utf8>);
typedef _CloseNative = Pointer<Utf8> Function(Uint64);
typedef _CloseDart = Pointer<Utf8> Function(int);
typedef _VoidNative = Pointer<Utf8> Function();
typedef _VoidDart = Pointer<Utf8> Function();
typedef _GrabNative = Pointer<Utf8> Function(Uint64);
typedef _GrabDart = Pointer<Utf8> Function(int);
typedef _PathNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _PathDart = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _UpsertNative = Pointer<Utf8> Function(
    Pointer<Utf8>, Pointer<Utf8>, Uint16, Pointer<Utf8>);
typedef _UpsertDart = Pointer<Utf8> Function(
    Pointer<Utf8>, Pointer<Utf8>, int, Pointer<Utf8>);
typedef _FbSizeNative = Int32 Function(Uint64, Pointer<Uint32>, Pointer<Uint32>);
typedef _FbSizeDart = int Function(int, Pointer<Uint32>, Pointer<Uint32>);
typedef _FbCopyNative = Int32 Function(Uint64, Pointer<Uint8>, IntPtr);
typedef _FbCopyDart = int Function(int, Pointer<Uint8>, int);
typedef _DesktopSizeNative = Pointer<Utf8> Function(Uint64, Uint32, Uint32);
typedef _DesktopSizeDart = Pointer<Utf8> Function(int, int, int);

class HelmBridge implements IHelmBridge {
  HelmBridge._(this._lib)
      : _hello = _lib.lookupFunction<_HelloNative, _HelloDart>('hh_hello'),
        _coreVersion =
            _lib.lookupFunction<_HelloNative, _HelloDart>('hh_core_version'),
        _free = _lib.lookupFunction<_FreeNative, _FreeDart>('hh_string_free'),
        _connect =
            _lib.lookupFunction<_ConnectNative, _ConnectDart>('hh_connect'),
        _poll = _lib.lookupFunction<_PollNative, _PollDart>('hh_poll_event'),
        _pointer =
            _lib.lookupFunction<_PtrNative, _PtrDart>('hh_send_pointer'),
        _key = _lib.lookupFunction<_KeyNative, _KeyDart>('hh_send_key'),
        _clipboard = _lib
            .lookupFunction<_ClipNative, _ClipDart>('hh_send_clipboard'),
        _close = _lib.lookupFunction<_CloseNative, _CloseDart>('hh_close'),
        _grab = _lib.lookupFunction<_GrabNative, _GrabDart>('hh_focus_grab'),
        _release =
            _lib.lookupFunction<_VoidNative, _VoidDart>('hh_focus_release'),
        _focusGet =
            _lib.lookupFunction<_VoidNative, _VoidDart>('hh_focus_get'),
        _regPath = _lib
            .lookupFunction<_PathNative, _PathDart>('hh_registry_set_path'),
        _regList =
            _lib.lookupFunction<_VoidNative, _VoidDart>('hh_registry_list'),
        _regUpsert = _lib
            .lookupFunction<_UpsertNative, _UpsertDart>('hh_registry_upsert'),
        _regUpsertJson = _lib
            .lookupFunction<_PathNative, _PathDart>('hh_registry_upsert_json'),
        _regRemove =
            _lib.lookupFunction<_PathNative, _PathDart>('hh_registry_remove'),
        _regMerge = _lib
            .lookupFunction<_PathNative, _PathDart>('hh_registry_merge_json'),
        _regExport =
            _lib.lookupFunction<_VoidNative, _VoidDart>('hh_registry_export'),
        _profileList =
            _lib.lookupFunction<_VoidNative, _VoidDart>('hh_profile_list'),
        _profileUpsert = _lib
            .lookupFunction<_PathNative, _PathDart>('hh_profile_upsert_json'),
        _profileRemove =
            _lib.lookupFunction<_PathNative, _PathDart>('hh_profile_remove'),
        _regResolve =
            _lib.lookupFunction<_PathNative, _PathDart>('hh_registry_resolve'),
        _fbSize = _lib.lookupFunction<_FbSizeNative, _FbSizeDart>('hh_fb_size'),
        _fbCopy = _lib.lookupFunction<_FbCopyNative, _FbCopyDart>('hh_fb_copy'),
        _requestDesktopSize = _lib.lookupFunction<_DesktopSizeNative, _DesktopSizeDart>(
            'hh_request_desktop_size');

  // ignore: unused_field
  final DynamicLibrary _lib;
  final _HelloDart _hello;
  final _HelloDart _coreVersion;
  final _FreeDart _free;
  final _ConnectDart _connect;
  final _PollDart _poll;
  final _PtrDart _pointer;
  final _KeyDart _key;
  final _ClipDart _clipboard;
  final _CloseDart _close;
  final _GrabDart _grab;
  final _VoidDart _release;
  final _VoidDart _focusGet;
  final _PathDart _regPath;
  final _VoidDart _regList;
  final _UpsertDart _regUpsert;
  final _PathDart _regUpsertJson;
  final _PathDart _regRemove;
  final _PathDart _regMerge;
  final _VoidDart _regExport;
  final _VoidDart _profileList;
  final _PathDart _profileUpsert;
  final _PathDart _profileRemove;
  final _PathDart _regResolve;
  final _FbSizeDart _fbSize;
  final _FbCopyDart _fbCopy;
  final _DesktopSizeDart _requestDesktopSize;

  /// Native scratch for `hh_fb_copy` (avoids malloc every frame).
  Pointer<Uint8>? _fbNative;
  int _fbNativeCap = 0;

  /// Dart heap scratch (avoids `Uint8List.fromList` allocate-every-frame).
  Uint8List? _fbDart;
  int _fbDartCap = 0;

  static HelmBridge open() {
    final name = Platform.isMacOS
        ? 'libhelmhost_ffi.dylib'
        : Platform.isWindows
            ? 'helmhost_ffi.dll'
            : 'libhelmhost_ffi.so';

    final candidates = <String>[
      if (Platform.environment['HELMHOST_FFI'] case final env?
          when env.isNotEmpty)
        env,
      '${File(Platform.resolvedExecutable).parent.path}/$name',
      '${File(Platform.resolvedExecutable).parent.path}/../Frameworks/$name',
      name,
    ];

    Object? last;
    for (final path in candidates) {
      try {
        return HelmBridge._(DynamicLibrary.open(path));
      } catch (e) {
        last = e;
      }
    }
    throw StateError(
      'Failed to load $name (build with scripts/build_client.sh first): $last',
    );
  }

  String _take(Pointer<Utf8> p) {
    try {
      return p.toDartString();
    } finally {
      _free(p);
    }
  }

  @override
  String hello() => _take(_hello());

  @override
  String coreVersion() => _take(_coreVersion());

  @override
  Future<void> initRegistry() async {
    final path = await AppPaths.connectionsJsonPath();
    final c = path.toNativeUtf8();
    try {
      final r = _take(_regPath(c));
      if (r.startsWith('ERR:')) throw StateError(r);
    } finally {
      malloc.free(c);
    }
  }

  Future<Directory> thumbsDir() async => AppPaths.thumbsDir();

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
    final h = host.toNativeUtf8();
    final u = (username ?? '').toNativeUtf8();
    final p = (password ?? '').toNativeUtf8();
    try {
      final r = _take(_connect(
        h,
        port,
        u,
        p,
        preferVencrypt ? 1 : 0,
        acceptInvalidCerts ? 1 : 0,
        bandwidthPreset.clamp(0, 2),
        qualityLevel == null ? -1 : qualityLevel.clamp(0, 9),
        compressLevel == null ? -1 : compressLevel.clamp(0, 9),
      ));
      if (r.startsWith('ERR:')) throw StateError(r.substring(4));
      return int.parse(r);
    } finally {
      malloc.free(h);
      malloc.free(u);
      malloc.free(p);
    }
  }

  @override
  Map<String, dynamic> pollEvent(int sessionId) {
    final r = _take(_poll(sessionId));
    if (r.startsWith('ERR:')) throw StateError(r);
    return jsonDecode(r) as Map<String, dynamic>;
  }

  @override
  (int, int) fbSize(int sessionId) {
    final w = malloc<Uint32>();
    final h = malloc<Uint32>();
    try {
      final rc = _fbSize(sessionId, w, h);
      if (rc != 0) throw StateError('hh_fb_size failed');
      return (w.value, h.value);
    } finally {
      malloc.free(w);
      malloc.free(h);
    }
  }

  /// Copy full RGBA8 framebuffer into a reusable buffer (one memcpy).
  /// Returned view is valid only until the next [fbCopy] call.
  @override
  Uint8List fbCopy(int sessionId, int width, int height) {
    final len = width * height * 4;
    if (len <= 0) throw StateError('invalid fb size');

    if (_fbNative == null || _fbNativeCap < len) {
      if (_fbNative != null) malloc.free(_fbNative!);
      _fbNative = malloc<Uint8>(len);
      _fbNativeCap = len;
    }
    final rc = _fbCopy(sessionId, _fbNative!, len);
    if (rc != 0) throw StateError('hh_fb_copy failed');

    if (_fbDart == null || _fbDartCap < len) {
      _fbDart = Uint8List(len);
      _fbDartCap = len;
    }
    _fbDart!.setRange(0, len, _fbNative!.asTypedList(len));
    return Uint8List.sublistView(_fbDart!, 0, len);
  }

  @override
  void sendPointer(int sessionId, int x, int y, int buttons) {
    final rc = _pointer(sessionId, x, y, buttons);
    if (rc != 0) throw StateError('hh_send_pointer failed');
  }

  @override
  void sendKey(int sessionId, bool down, int keysym) {
    final rc = _key(sessionId, down ? 1 : 0, keysym);
    if (rc != 0) throw StateError('hh_send_key failed');
  }

  @override
  void sendClipboard(int sessionId, String text) {
    final c = text.toNativeUtf8();
    try {
      final r = _take(_clipboard(sessionId, c));
      if (r.startsWith('ERR:')) throw StateError(r);
    } finally {
      malloc.free(c);
    }
  }

  /// TigerVNC RemoteResize: ask server to set remote FB to [width]×[height].
  @override
  void requestDesktopSize(int sessionId, int width, int height) {
    final r = _take(_requestDesktopSize(sessionId, width, height));
    if (r.startsWith('ERR:')) throw StateError(r);
  }

  @override
  void close(int sessionId) {
    final r = _take(_close(sessionId));
    if (r.startsWith('ERR:')) throw StateError(r);
  }

  @override
  void grab(int sessionId) {
    final r = _take(_grab(sessionId));
    if (r.startsWith('ERR:')) throw StateError(r);
  }

  @override
  void releaseFocus() {
    final r = _take(_release());
    if (r.startsWith('ERR:')) throw StateError(r);
  }

  String focusGet() => _take(_focusGet());

  @override
  List<dynamic> registryList() {
    final r = _take(_regList());
    if (r.startsWith('ERR:')) throw StateError(r);
    return jsonDecode(r) as List<dynamic>;
  }

  void registryUpsert(
      String id, String host, int port, String? displayName) {
    final i = id.toNativeUtf8();
    final h = host.toNativeUtf8();
    final d = (displayName ?? '').toNativeUtf8();
    try {
      final r = _take(_regUpsert(i, h, port, d));
      if (r.startsWith('ERR:')) throw StateError(r);
    } finally {
      malloc.free(i);
      malloc.free(h);
      malloc.free(d);
    }
  }

  @override
  void registryUpsertJson(Map<String, dynamic> entry) {
    final c = jsonEncode(entry).toNativeUtf8();
    try {
      final r = _take(_regUpsertJson(c));
      if (r.startsWith('ERR:')) throw StateError(r);
    } finally {
      malloc.free(c);
    }
  }

  @override
  void registryRemove(String id) {
    final c = id.toNativeUtf8();
    try {
      final r = _take(_regRemove(c));
      if (r.startsWith('ERR:')) throw StateError(r);
    } finally {
      malloc.free(c);
    }
  }

  @override
  String registryExport() {
    final r = _take(_regExport());
    if (r.startsWith('ERR:')) throw StateError(r);
    return r;
  }

  @override
  void registryMergeJson(String json) {
    final c = json.toNativeUtf8();
    try {
      final r = _take(_regMerge(c));
      if (r.startsWith('ERR:')) throw StateError(r);
    } finally {
      malloc.free(c);
    }
  }

  @override
  List<dynamic> profileList() {
    final r = _take(_profileList());
    if (r.startsWith('ERR:')) throw StateError(r);
    return jsonDecode(r) as List<dynamic>;
  }

  @override
  void profileUpsertJson(Map<String, dynamic> profile) {
    final encoded = jsonEncode(profile);
    // ignore: avoid_print — temporary diagnose for default_display persistence
    debugPrint('[bridge] profileUpsertJson $encoded');
    final c = encoded.toNativeUtf8();
    try {
      final r = _take(_profileUpsert(c));
      if (r.startsWith('ERR:')) throw StateError(r);
      debugPrint('[bridge] profileUpsertJson ok');
    } finally {
      malloc.free(c);
    }
  }

  @override
  void profileRemove(String id) {
    final c = id.toNativeUtf8();
    try {
      final r = _take(_profileRemove(c));
      if (r.startsWith('ERR:')) throw StateError(r);
    } finally {
      malloc.free(c);
    }
  }

  @override
  Map<String, dynamic> registryResolve(String id) {
    final c = id.toNativeUtf8();
    try {
      final r = _take(_regResolve(c));
      if (r.startsWith('ERR:')) throw StateError(r);
      return Map<String, dynamic>.from(jsonDecode(r) as Map);
    } finally {
      malloc.free(c);
    }
  }
}
