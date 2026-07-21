import 'dart:convert';
import 'dart:io';

import 'app_paths.dart';

/// Thrown when credential persistence fails.
class CredentialStoreException implements Exception {
  CredentialStoreException(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

abstract class ICredentialStore {
  Future<String?> readPassword(String entryId);
  Future<void> writePassword(String entryId, String password);
  Future<void> deletePassword(String entryId);
}

/// File-backed store under `~/.helmhost/credentials.vault`.
///
/// Used instead of Keychain so Debug builds with ad-hoc signing
/// (`CODE_SIGN_IDENTITY = "-"`) can save passwords without a
/// development certificate / Keychain entitlement.
class FileCredentialStore implements ICredentialStore {
  FileCredentialStore({Directory? root}) : _rootOverride = root;

  final Directory? _rootOverride;
  File? _file;
  Map<String, String>? _cache;

  static const _fileName = AppPaths.credentialsFileName;
  // Obfuscation only — not a substitute for Keychain on signed Release builds.
  static const _xorKey = 'helmhost.local.cred.v1';

  Future<File> _resolveFile() async {
    if (_file != null) return _file!;
    final root = _rootOverride ?? await AppPaths.root();
    _file = File('${root.path}/$_fileName');
    return _file!;
  }

  Future<Map<String, String>> _load() async {
    if (_cache != null) return _cache!;
    final f = await _resolveFile();
    if (!await f.exists()) {
      _cache = {};
      return _cache!;
    }
    try {
      final raw = jsonDecode(await f.readAsString());
      if (raw is! Map) {
        _cache = {};
        return _cache!;
      }
      final out = <String, String>{};
      raw.forEach((k, v) {
        if (k is String && v is String) {
          out[k] = _decode(v);
        }
      });
      _cache = out;
      return out;
    } catch (e) {
      throw CredentialStoreException('Could not read saved passwords', e);
    }
  }

  Future<void> _save(Map<String, String> data) async {
    final f = await _resolveFile();
    final encoded = <String, String>{
      for (final e in data.entries) e.key: _encode(e.value),
    };
    try {
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode(encoded));
      _cache = Map<String, String>.from(data);
    } catch (e) {
      throw CredentialStoreException('Could not save password', e);
    }
  }

  static String _encode(String plain) {
    final key = utf8.encode(_xorKey);
    final bytes = utf8.encode(plain);
    final out = List<int>.generate(
      bytes.length,
      (i) => bytes[i] ^ key[i % key.length],
    );
    return base64Encode(out);
  }

  static String _decode(String stored) {
    final key = utf8.encode(_xorKey);
    final bytes = base64Decode(stored);
    final out = List<int>.generate(
      bytes.length,
      (i) => bytes[i] ^ key[i % key.length],
    );
    return utf8.decode(out);
  }

  @override
  Future<String?> readPassword(String entryId) async {
    final data = await _load();
    return data[entryId];
  }

  @override
  Future<void> writePassword(String entryId, String password) async {
    final data = await _load();
    data[entryId] = password;
    await _save(data);
  }

  @override
  Future<void> deletePassword(String entryId) async {
    final data = await _load();
    if (data.remove(entryId) == null) return;
    await _save(data);
  }
}

class MemoryCredentialStore implements ICredentialStore {
  final _map = <String, String>{};

  @override
  Future<void> deletePassword(String entryId) async {
    _map.remove(entryId);
  }

  @override
  Future<String?> readPassword(String entryId) async => _map[entryId];

  @override
  Future<void> writePassword(String entryId, String password) async {
    _map[entryId] = password;
  }
}

ICredentialStore createCredentialStore() => FileCredentialStore();
