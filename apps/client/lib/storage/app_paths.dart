import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// HelmHost user data lives under `~/.helmhost` on every desktop OS.
///
/// Layout:
/// ```
/// ~/.helmhost/
///   connections.json
///   credentials.vault
///   thumbs/
/// ```
///
/// On macOS App Sandbox, `HOME` is the container
/// (`…/Library/Containers/<bundle>/Data`). We strip that suffix so the app
/// uses the real user `~/.helmhost` (Release entitlement:
/// `temporary-exception…/.helmhost/`).
class AppPaths {
  AppPaths._();

  static const dirName = '.helmhost';
  static const connectionsFileName = 'connections.json';
  static const credentialsFileName = 'credentials.vault';
  static const thumbsDirName = 'thumbs';

  /// Historical Flutter macOS / Linux bundle folder name under Application Support.
  static const legacyBundleFolder = 'dev.helmhost.helmhostClient';

  static Directory? _root;
  static bool _migrated = false;
  static String? _realHome;

  /// Absolute path to the user's real home (not the App Sandbox container).
  static String? realHomeDirectory() {
    if (_realHome != null) return _realHome;

    if (Platform.isWindows) {
      final profile = Platform.environment['USERPROFILE'];
      if (profile != null && profile.isNotEmpty) {
        _realHome = profile;
      }
      return _realHome;
    }

    var home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return null;

    // Sandboxed macOS: HOME = /Users/you/Library/Containers/<id>/Data
    const marker = '/Library/Containers/';
    final idx = home.indexOf(marker);
    if (idx > 0) {
      home = home.substring(0, idx);
    }
    _realHome = home;
    return _realHome;
  }

  /// `~/.helmhost` (created if missing). Runs legacy migration once.
  static Future<Directory> root() async {
    if (_root != null) {
      await _maybeMigrate();
      return _root!;
    }
    final home = realHomeDirectory();
    if (home == null || home.isEmpty) {
      final fallback = await getApplicationSupportDirectory();
      _root = Directory(fallback.path);
    } else {
      _root = Directory('$home/$dirName');
    }
    if (!await _root!.exists()) {
      await _root!.create(recursive: true);
    }
    await _maybeMigrate();
    return _root!;
  }

  static Future<String> connectionsJsonPath() async {
    final r = await root();
    return '${r.path}/$connectionsFileName';
  }

  static Future<Directory> thumbsDir() async {
    final r = await root();
    final t = Directory('${r.path}/$thumbsDirName');
    if (!await t.exists()) await t.create(recursive: true);
    return t;
  }

  static Future<void> _maybeMigrate() async {
    if (_migrated || _root == null) return;
    _migrated = true;

    final destConn = File('${_root!.path}/$connectionsFileName');
    if (await destConn.exists()) return;

    final legacy = await _pickLegacyRoot();
    if (legacy == null) return;

    Future<void> copyIfPresent(String name, {bool recursive = false}) async {
      final src = recursive
          ? Directory('${legacy.path}/$name')
          : File('${legacy.path}/$name');
      if (!await src.exists()) return;
      final destPath = '${_root!.path}/$name';
      if (recursive) {
        final dest = Directory(destPath);
        if (await dest.exists()) return;
        await _copyDir(src as Directory, dest);
      } else {
        final dest = File(destPath);
        if (await dest.exists()) return;
        await (src as File).copy(dest.path);
      }
    }

    await copyIfPresent(connectionsFileName);
    await copyIfPresent(credentialsFileName);
    await copyIfPresent(thumbsDirName, recursive: true);
  }

  /// Prefer non-container Application Support; also consider container `.helmhost`.
  static Future<Directory?> _pickLegacyRoot() async {
    final candidates = <Directory>[];
    final home = realHomeDirectory();

    if (home != null && home.isNotEmpty) {
      if (Platform.isMacOS) {
        candidates.add(
          Directory('$home/Library/Application Support/$legacyBundleFolder'),
        );
        candidates.add(
          Directory(
            '$home/Library/Containers/$legacyBundleFolder/Data/$dirName',
          ),
        );
      } else if (Platform.isLinux) {
        candidates.add(
          Directory('$home/.local/share/$legacyBundleFolder'),
        );
      } else if (Platform.isWindows) {
        final appData = Platform.environment['APPDATA'];
        if (appData != null && appData.isNotEmpty) {
          candidates.add(Directory('$appData\\$legacyBundleFolder'));
        }
      }
    }

    try {
      candidates.add(await getApplicationSupportDirectory());
    } catch (_) {}

    Directory? best;
    var bestSize = -1;
    for (final dir in candidates) {
      if (!await dir.exists()) continue;
      final conn = File('${dir.path}/$connectionsFileName');
      if (!await conn.exists()) continue;
      final size = await conn.length();
      if (size > bestSize) {
        best = dir;
        bestSize = size;
      }
    }
    return best;
  }

  static Future<void> _copyDir(Directory src, Directory dest) async {
    await dest.create(recursive: true);
    await for (final entity in src.list(recursive: false)) {
      final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      if (entity is File) {
        await entity.copy('${dest.path}/$name');
      } else if (entity is Directory) {
        await _copyDir(entity, Directory('${dest.path}/$name'));
      }
    }
  }
}
