import 'dart:io';

/// Fixed startup phases only; does not record connection details or secrets.
void recordStartupPhase(String phase) {
  if (!Platform.isWindows) return;
  final local = Platform.environment['LOCALAPPDATA'];
  if (local == null || local.isEmpty) return;
  try {
    final file = File('$local/Helmhost/logs/startup-dart.log');
    file.parent.createSync(recursive: true);
    if (file.existsSync() && file.lengthSync() > 1024 * 1024) {
      file.writeAsStringSync('');
    }
    file.writeAsStringSync(
      '${DateTime.now().toUtc().toIso8601String()} pid=$pid $phase\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {
    // Diagnostics must not prevent the application from starting.
  }
}
