import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'bridge.dart';

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
  HelmBridge bridge,
  String entryId,
  int sessionId,
) async {
  try {
    final (w, h) = bridge.fbSize(sessionId);
    if (w <= 0 || h <= 0) return;
    final rgba = bridge.fbCopy(sessionId, w, h);
    final jpg = encodeFbJpegThumb(rgba, w, h);
    if (jpg == null) return;
    final support = await getApplicationSupportDirectory();
    final thumbs = Directory('${support.path}/thumbs');
    if (!await thumbs.exists()) await thumbs.create(recursive: true);
    final safe = entryId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final rel = 'thumbs/$safe.jpg';
    await File('${support.path}/$rel').writeAsBytes(jpg);
    final list = bridge.registryList();
    Map<String, dynamic> entry = {
      'id': entryId,
      'host': entryId.split(':').first,
      'port': int.tryParse(entryId.split(':').last) ?? 5900,
      'thumb_path': rel,
    };
    for (final raw in list) {
      final m = raw as Map<String, dynamic>;
      if (m['id'] == entryId) {
        entry = {...m, 'thumb_path': rel};
        break;
      }
    }
    bridge.registryUpsertJson(entry);
  } catch (_) {}
}
