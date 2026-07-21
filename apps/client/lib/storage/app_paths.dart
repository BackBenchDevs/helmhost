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
/// On first launch, migrates files from the former Application Support
/// directory (`…/dev.helmhost.helmhostClient/`) if present. Prefers the
/// non-container macOS Application Support tree over the sandboxed Container
/// copy (which may be stale).
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

  /// `~/.helmhost` (created if missing). Runs legacy migration once.
  static Future<Directory> root() async {
    if (_root != null) {
      await _maybeMigrate();
      return _root!;
    }
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'];
    if (home == null || home.isEmpty) {
      // Extremely rare — fall back to Application Support.
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

  /// Prefer non-container Application Support; fall back to path_provider.
  static Future<Directory?> _pickLegacyRoot() async {
    final candidates = <Directory>[];

    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      if (Platform.isMacOS) {
        candidates.add(
          Directory('$home/Library/Application Support/$legacyBundleFolder'),
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
    int bestSize = -1;
    for (final dir in candidates) {
      if (!await dir.exists()) continue;
      final conn = File('${dir.path}/$connectionsFileName');
      if (!await conn.exists()) continue;
      final size = await conn.length();
      // Prefer first candidate when sizes tie (non-container listed first).
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
