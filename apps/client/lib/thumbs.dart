import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'bridge.dart';
import 'storage/app_paths.dart';

Uint8List? encodeFbJpegThumb(Uint8List rgba, int w, int h, {int width = 320}) {
  if (w <= 0 || h <= 0 || rgba.length < w * h * 4) return null;
  final decoded = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: rgba.buffer,
    order: img.ChannelOrder.rgba,
  );
  final th = (h * width / w).round().clamp(1, 2000);
  final small = img.copyResize(decoded, width: width, height: th);
  return Uint8List.fromList(img.encodeJpg(small, quality: 70));
}

Future<void> saveSessionThumb(
  IHelmBridge bridge,
  String entryId,
  int sessionId,
) async {
  try {
    final (w, h) = bridge.fbSize(sessionId);
    if (w <= 0 || h <= 0) return;
    final rgba = bridge.fbCopy(sessionId, w, h);
    final jpg = encodeFbJpegThumb(rgba, w, h);
    if (jpg == null) return;
    final thumbs = await AppPaths.thumbsDir();
    final safe = entryId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final rel = '${AppPaths.thumbsDirName}/$safe.jpg';
    await File('${thumbs.path}/$safe.jpg').writeAsBytes(jpg);
    final list = bridge.registryList();
    Map<String, dynamic> entry = {
      'id': entryId,
      'host': entryId.split(':').first,
      'port': int.tryParse(entryId.split(':').last) ?? 5900,
      'thumb_path': rel,
    };
    for (final raw in list) {
      final m = Map<String, dynamic>.from(raw as Map);
      if (m['id'] == entryId) {
        entry = {...m, 'thumb_path': rel};
        break;
      }
    }
    bridge.registryUpsertJson(entry);
  } catch (_) {}
}
