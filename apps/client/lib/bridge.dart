import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';

typedef _HelloNative = Pointer<Utf8> Function();
typedef _HelloDart = Pointer<Utf8> Function();
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _FreeDart = void Function(Pointer<Utf8>);
typedef _ConnectNative = Pointer<Utf8> Function(
    Pointer<Utf8>, Uint16, Pointer<Utf8>);
typedef _ConnectDart = Pointer<Utf8> Function(
    Pointer<Utf8>, int, Pointer<Utf8>);
typedef _PollNative = Pointer<Utf8> Function(Uint64);
typedef _PollDart = Pointer<Utf8> Function(int);
typedef _PtrNative = Pointer<Utf8> Function(Uint64, Int32, Int32, Uint8);
typedef _PtrDart = Pointer<Utf8> Function(int, int, int, int);
typedef _KeyNative = Pointer<Utf8> Function(Uint64, Uint8, Uint32);
typedef _KeyDart = Pointer<Utf8> Function(int, int, int);
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

/// Native bridge to `helmhost-ffi` (C ABI; FRB-ready `hello` surface).
class HelmBridge {
  HelmBridge._(this._lib)
      : _hello = _lib.lookupFunction<_HelloNative, _HelloDart>('hh_hello'),
        _free = _lib.lookupFunction<_FreeNative, _FreeDart>('hh_string_free'),
        _connect =
            _lib.lookupFunction<_ConnectNative, _ConnectDart>('hh_connect'),
        _poll = _lib.lookupFunction<_PollNative, _PollDart>('hh_poll_event'),
        _pointer =
            _lib.lookupFunction<_PtrNative, _PtrDart>('hh_send_pointer'),
        _key = _lib.lookupFunction<_KeyNative, _KeyDart>('hh_send_key'),
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
            .lookupFunction<_UpsertNative, _UpsertDart>('hh_registry_upsert');

  // Keep library alive for the process lifetime.
  // ignore: unused_field
  final DynamicLibrary _lib;
  final _HelloDart _hello;
  final _FreeDart _free;
  final _ConnectDart _connect;
  final _PollDart _poll;
  final _PtrDart _pointer;
  final _KeyDart _key;
  final _CloseDart _close;
  final _GrabDart _grab;
  final _VoidDart _release;
  final _VoidDart _focusGet;
  final _PathDart _regPath;
  final _VoidDart _regList;
  final _UpsertDart _regUpsert;

  static HelmBridge open() {
    final name = Platform.isMacOS
        ? 'libhelmhost_ffi.dylib'
        : Platform.isWindows
            ? 'helmhost_ffi.dll'
            : 'libhelmhost_ffi.so';
    final candidates = <String>[
      name,
      '../target/debug/$name',
      '../target/release/$name',
      '../../target/debug/$name',
      '../../target/release/$name',
      '${Directory.current.path}/../../target/debug/$name',
      '${Directory.current.path}/../../target/release/$name',
    ];
    Object? last;
    for (final path in candidates) {
      try {
        return HelmBridge._(DynamicLibrary.open(path));
      } catch (e) {
        last = e;
      }
    }
    throw StateError('Failed to load $name: $last');
  }

  String _take(Pointer<Utf8> p) {
    try {
      return p.toDartString();
    } finally {
      _free(p);
    }
  }

  String hello() => _take(_hello());

  Future<void> initRegistry() async {
    final dir = await getApplicationSupportDirectory();
    final path = '${dir.path}/connections.json';
    final c = path.toNativeUtf8();
    try {
      final r = _take(_regPath(c));
      if (r.startsWith('ERR:')) throw StateError(r);
    } finally {
      malloc.free(c);
    }
  }

  int connect(String host, int port, String? password) {
    final h = host.toNativeUtf8();
    final p = (password ?? '').toNativeUtf8();
    try {
      final r = _take(_connect(h, port, p));
      if (r.startsWith('ERR:')) throw StateError(r);
      return int.parse(r);
    } finally {
      malloc.free(h);
      malloc.free(p);
    }
  }

  Map<String, dynamic> pollEvent(int sessionId) {
    final r = _take(_poll(sessionId));
    if (r.startsWith('ERR:')) throw StateError(r);
    return jsonDecode(r) as Map<String, dynamic>;
  }

  void sendPointer(int sessionId, int x, int y, int buttons) {
    final r = _take(_pointer(sessionId, x, y, buttons));
    if (r.startsWith('ERR:')) throw StateError(r);
  }

  void sendKey(int sessionId, bool down, int keysym) {
    final r = _take(_key(sessionId, down ? 1 : 0, keysym));
    if (r.startsWith('ERR:')) throw StateError(r);
  }

  void close(int sessionId) {
    final r = _take(_close(sessionId));
    if (r.startsWith('ERR:')) throw StateError(r);
  }

  void grab(int sessionId) {
    final r = _take(_grab(sessionId));
    if (r.startsWith('ERR:')) throw StateError(r);
  }

  void releaseFocus() {
    final r = _take(_release());
    if (r.startsWith('ERR:')) throw StateError(r);
  }

  String focusGet() => _take(_focusGet());

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
}
