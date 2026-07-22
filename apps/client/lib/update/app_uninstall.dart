import 'dart:io';

/// Launch the platform-native uninstaller. Does not delete `~/.helmhost`.
abstract class IAppUninstaller {
  /// Starts uninstall UI / elevated remove. May quit the app afterward.
  Future<void> uninstall();
}

IAppUninstaller createAppUninstaller() {
  if (Platform.isMacOS) return MacosAppUninstaller();
  if (Platform.isWindows) return WindowsAppUninstaller();
  if (Platform.isLinux) return LinuxAppUninstaller();
  return NoopAppUninstaller();
}

class NoopAppUninstaller implements IAppUninstaller {
  @override
  Future<void> uninstall() async {}
}

class MacosAppUninstaller implements IAppUninstaller {
  @override
  Future<void> uninstall() async {
    final r = await Process.run('open', ['-a', 'Uninstall Helmhost']);
    if (r.exitCode != 0) {
      // Fallback: open Applications path if Launch Services name lookup fails.
      final alt = await Process.run('open', [
        '/Applications/Uninstall Helmhost.app',
      ]);
      if (alt.exitCode != 0) {
        throw StateError(
          'Uninstall Helmhost.app not found. Remove /Applications/Helmhost.app '
          'manually, then: pkgutil --forget com.bbdevs.helmhost',
        );
      }
    }
  }
}

class WindowsAppUninstaller implements IAppUninstaller {
  static const _appId = '{A7C3E9F1-4B2D-4E8A-9C1F-6D5B8A0E2F34}_is1';

  @override
  Future<void> uninstall() async {
    // Inno writes UninstallString under this key (32- or 64-bit view).
    final ps = '''
\$key = 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\$_appId'
if (-not (Test-Path \$key)) {
  \$key = 'HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\$_appId'
}
if (-not (Test-Path \$key)) {
  \$key = 'HKLM:\\Software\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\$_appId'
}
if (-not (Test-Path \$key)) { throw 'Helmhost uninstall entry not found' }
\$u = (Get-ItemProperty \$key).UninstallString
if (-not \$u) { throw 'UninstallString missing' }
Start-Process -FilePath \$u.Trim('"') -Wait
''';
    final r = await Process.run('powershell.exe', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      ps,
    ]);
    if (r.exitCode != 0) {
      throw StateError('Uninstall failed: ${r.stderr}'.trim());
    }
  }
}

class LinuxAppUninstaller implements IAppUninstaller {
  @override
  Future<void> uninstall() async {
    final r = await Process.run('pkexec', [
      'apt-get',
      'remove',
      '-y',
      'helmhost',
    ]);
    if (r.exitCode != 0) {
      throw StateError(
        'apt remove failed: ${r.stderr}\nTry: sudo apt remove helmhost',
      );
    }
  }
}
