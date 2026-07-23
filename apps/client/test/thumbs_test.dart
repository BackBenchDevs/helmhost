import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/thumbs.dart';

import 'helpers/fake_helm_bridge.dart';

void main() {
  group('encodeFbJpegThumb', () {
    test('encodes synthetic RGBA', () {
      const w = 4;
      const h = 4;
      final rgba = Uint8List(w * h * 4);
      for (var i = 0; i < rgba.length; i += 4) {
        rgba[i] = 255;
        rgba[i + 1] = 0;
        rgba[i + 2] = 0;
        rgba[i + 3] = 255;
      }
      final jpg = encodeFbJpegThumb(rgba, w, h, width: 2);
      expect(jpg, isNotNull);
      expect(jpg!, isNotEmpty);
    });

    test('rejects bad dims and short buffer', () {
      expect(encodeFbJpegThumb(Uint8List(0), 0, 0), isNull);
      expect(encodeFbJpegThumb(Uint8List(4), 2, 2), isNull);
    });
  });

  group('saveSessionThumb', () {
    test('writes jpeg and upserts thumb_path via fake bridge', () async {
      final rgba = Uint8List(2 * 2 * 4);
      for (var i = 0; i < rgba.length; i += 4) {
        rgba[i] = 0;
        rgba[i + 1] = 255;
        rgba[i + 2] = 0;
        rgba[i + 3] = 255;
      }
      final bridge = FakeHelmBridge(
        width: 2,
        height: 2,
        rgba: rgba,
        registry: [
          {
            'id': 'lab:5901',
            'host': 'lab',
            'port': 5901,
            'display_name': 'Lab',
          },
        ],
      );
      await saveSessionThumb(bridge, 'lab:5901', 1);
      expect(bridge.upserts, isNotEmpty);
      final entry = bridge.upserts.last;
      expect(entry['id'], 'lab:5901');
      expect(entry['thumb_path'], startsWith('thumbs/'));
      expect(entry['display_name'], 'Lab');
      final rel = entry['thumb_path'] as String;
      final home = Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'];
      expect(home, isNotNull);
      final file = File('$home/.helmhost/$rel');
      expect(await file.exists(), isTrue);
      expect(await file.length(), greaterThan(0));
    });
  });
}
