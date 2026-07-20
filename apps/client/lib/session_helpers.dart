// Pure helpers for Hub session dedup / keys (unit-testable).

String sessionKey(String host, int port) => '$host:$port';

class OpenSessionRef {
  const OpenSessionRef({
    required this.id,
    required this.host,
    required this.port,
  });

  final int id;
  final String host;
  final int port;

  String get key => sessionKey(host, port);
}

/// Returns the first open session matching host:port, if any.
OpenSessionRef? findOpenByHostPort(
  Iterable<OpenSessionRef> sessions,
  String host,
  int port,
) {
  final want = sessionKey(host.trim(), port);
  for (final s in sessions) {
    if (sessionKey(s.host.trim(), s.port) == want) return s;
  }
  return null;
}

/// Local framebuffer display modes (no remote SetDesktopSize).
enum ViewScaleMode {
  fit,
  fill,
  oneToOne,
}

extension ViewScaleModeX on ViewScaleMode {
  String get label {
    switch (this) {
      case ViewScaleMode.fit:
        return 'Fit';
      case ViewScaleMode.fill:
        return 'Fill';
      case ViewScaleMode.oneToOne:
        return '1:1';
    }
  }
}
