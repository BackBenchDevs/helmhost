import 'dart:convert';
import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../gen/app_version.dart';

/// Stable Pages feed (Sparkle / WinSparkle). Channel selects which file.
String appcastFeedUrl({String? channel}) {
  final ch = channel ?? kAppChannel;
  final file = ch == 'rcs' ? 'appcast-rcs.xml' : 'appcast.xml';
  return 'https://backbenchdevs.github.io/helmhost/$file';
}

/// Cross-platform update facade.
abstract class IAppUpdater {
  Future<void> init();
  Future<void> checkForUpdates({bool userInitiated = true});
}

IAppUpdater createAppUpdater({http.Client? httpClient}) {
  if (Platform.isMacOS || Platform.isWindows) {
    return SparkleAppUpdater();
  }
  if (Platform.isLinux) {
    return LinuxDebAppUpdater(httpClient: httpClient ?? http.Client());
  }
  return NoopAppUpdater();
}

class NoopAppUpdater implements IAppUpdater {
  @override
  Future<void> init() async {}

  @override
  Future<void> checkForUpdates({bool userInitiated = true}) async {}
}

/// macOS Sparkle (Ed25519) + Windows WinSparkle (DSA-4096).
class SparkleAppUpdater implements IAppUpdater {
  var _ready = false;

  @override
  Future<void> init() async {
    if (kIsWeb || !(Platform.isMacOS || Platform.isWindows)) return;
    await autoUpdater.setFeedURL(appcastFeedUrl());
    await autoUpdater.setScheduledCheckInterval(86400);
    _ready = true;
  }

  @override
  Future<void> checkForUpdates({bool userInitiated = true}) async {
    if (!_ready) await init();
    await autoUpdater.checkForUpdates();
  }
}

/// Linux: compare GitHub Releases semver, download matching .deb, elevate install.
class LinuxDebAppUpdater implements IAppUpdater {
  LinuxDebAppUpdater({required http.Client httpClient}) : _http = httpClient;

  final http.Client _http;
  static const _repo = 'BackBenchDevs/helmhost';

  @override
  Future<void> init() async {}

  @override
  Future<void> checkForUpdates({bool userInitiated = true}) async {
    final release = await _pickRelease();
    if (release == null) {
      throw StateError('No suitable GitHub release found');
    }
    final remote =
        release.tag.replaceFirst(RegExp(r'^v'), '').split('-').first;
    if (!isAppVersionNewer(remote, kAppVersion)) {
      if (userInitiated) {
        throw StateError('Already up to date (v$kAppVersion)');
      }
      return;
    }
    Map<String, dynamic>? asset;
    for (final a in release.assets) {
      final name = a['name'] as String? ?? '';
      if (name.endsWith('.deb')) {
        asset = a;
        break;
      }
    }
    if (asset == null) {
      throw StateError('No .deb asset on ${release.tag}');
    }
    final url = asset['browser_download_url'] as String;
    final name = asset['name'] as String;
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, name));
    final resp = await _http.get(Uri.parse(url));
    if (resp.statusCode != 200) {
      throw StateError('Download failed (${resp.statusCode})');
    }
    await file.writeAsBytes(resp.bodyBytes);
    final install = await Process.run('pkexec', [
      'apt-get',
      'install',
      '-y',
      file.path,
    ]);
    if (install.exitCode != 0) {
      throw StateError('apt install failed: ${install.stderr}'.trim());
    }
  }

  Future<_GhRelease?> _pickRelease() async {
    final wantRc = kAppChannel == 'rcs';
    final uri = Uri.https('api.github.com', '/repos/$_repo/releases', {
      'per_page': '20',
    });
    final resp = await _http.get(
      uri,
      headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'helmhost/$kAppVersion',
      },
    );
    if (resp.statusCode != 200) {
      throw StateError('GitHub API ${resp.statusCode}');
    }
    final list = jsonDecode(resp.body) as List<dynamic>;
    for (final raw in list) {
      final m = Map<String, dynamic>.from(raw as Map);
      if (m['draft'] == true) continue;
      final tag = m['tag_name'] as String? ?? '';
      final isRc = tag.contains('-rc.');
      if (wantRc != isRc) continue;
      final assets = (m['assets'] as List?) ?? const [];
      return _GhRelease(
        tag: tag,
        assets: assets
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );
    }
    return null;
  }

}

/// True when [remote] is a newer semver than [local] (major.minor.patch).
bool isAppVersionNewer(String remote, String local) {
  List<int> parts(String v) =>
      v.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final a = parts(remote);
  final b = parts(local);
  for (var i = 0; i < 3; i++) {
    final av = i < a.length ? a[i] : 0;
    final bv = i < b.length ? b[i] : 0;
    if (av != bv) return av > bv;
  }
  return false;
}

class _GhRelease {
  _GhRelease({required this.tag, required this.assets});
  final String tag;
  final List<Map<String, dynamic>> assets;
}
