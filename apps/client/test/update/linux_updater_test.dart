import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/gen/app_version.dart';
import 'package:helmhost/session/fb_texture.dart';
import 'package:helmhost/update/app_updater.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('DamageRect', () {
    test('union expands bounds', () {
      const a = DamageRect(x: 0, y: 0, w: 10, h: 10);
      const b = DamageRect(x: 5, y: 5, w: 10, h: 10);
      final u = a.union(b);
      expect(u.x, 0);
      expect(u.y, 0);
      expect(u.w, 15);
      expect(u.h, 15);
      expect(const DamageRect(x: 0, y: 0, w: 0, h: 1).isEmpty, isTrue);
    });
  });

  group('LinuxDebAppUpdater', () {
    test('throws already up to date when remote equals local', () async {
      final client = MockClient((req) async {
        expect(req.url.host, 'api.github.com');
        return http.Response(
          jsonEncode([
            {
              'tag_name': 'v$kAppVersion',
              'draft': false,
              'assets': [
                {
                  'name': 'helmhost.deb',
                  'browser_download_url': 'https://example.com/x.deb',
                },
              ],
            },
          ]),
          200,
        );
      });
      final updater = LinuxDebAppUpdater(httpClient: client);
      expect(
        () => updater.checkForUpdates(userInitiated: true),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Already up to date'),
          ),
        ),
      );
    });

    test('throws when no matching channel release', () async {
      final client = MockClient((req) async {
        return http.Response(
          jsonEncode([
            {
              'tag_name': 'v9.9.9-rc.1',
              'draft': false,
              'assets': [
                {
                  'name': 'helmhost.deb',
                  'browser_download_url': 'https://example.com/x.deb',
                },
              ],
            },
          ]),
          200,
        );
      });
      // Stable channel ignores -rc tags.
      final updater = LinuxDebAppUpdater(httpClient: client);
      if (kAppChannel == 'rcs') {
        // On rcs builds, an rc tag is suitable; skip this assertion.
        return;
      }
      expect(
        () => updater.checkForUpdates(userInitiated: true),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('No suitable'),
          ),
        ),
      );
    });
  });
}
