import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Remote cursor shape from RFB Cursor encodings (local OS/sprite path).
class RemoteCursorShape {
  const RemoteCursorShape({
    required this.width,
    required this.height,
    required this.hotspotX,
    required this.hotspotY,
    required this.rgba,
  });

  final int width;
  final int height;
  final int hotspotX;
  final int hotspotY;
  final Uint8List rgba;

  bool get isEmpty =>
      width <= 0 || height <= 0 || rgba.isEmpty || rgba.length < width * height * 4;

  /// Parse FFI `cursor_changed` JSON (`rgba_b64` base64 RGBA8).
  static RemoteCursorShape? fromPollEvent(Map<String, dynamic> ev) {
    if (ev['type'] != 'cursor_changed') return null;
    final w = (ev['w'] as num?)?.toInt() ?? 0;
    final h = (ev['h'] as num?)?.toInt() ?? 0;
    final hx = (ev['hotspot_x'] as num?)?.toInt() ?? 0;
    final hy = (ev['hotspot_y'] as num?)?.toInt() ?? 0;
    final b64 = ev['rgba_b64'] as String? ?? '';
    if (w <= 0 || h <= 0 || b64.isEmpty) {
      return RemoteCursorShape(
        width: 0,
        height: 0,
        hotspotX: hx,
        hotspotY: hy,
        rgba: Uint8List(0),
      );
    }
    final rgba = base64Decode(b64);
    if (rgba.length < w * h * 4) return null;
    return RemoteCursorShape(
      width: w,
      height: h,
      hotspotX: hx,
      hotspotY: hy,
      rgba: Uint8List.fromList(rgba),
    );
  }
}

Future<ui.Image?> decodeCursorImage(RemoteCursorShape shape) async {
  if (shape.isEmpty) return null;
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    shape.rgba,
    shape.width,
    shape.height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}
