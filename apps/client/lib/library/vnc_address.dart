/// RealVNC-compatible VNC address: `host`, `host:display`, or `host::port`.
class VncAddress {
  const VncAddress({
    required this.host,
    required this.port,
    this.displayNumber,
  });

  final String host;
  final int port;
  final int? displayNumber;

  String get sessionId => '$host:$port';
}

class VncAddressParseException implements Exception {
  VncAddressParseException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Parse a VNC server address.
///
/// - `lab-pc` → host `lab-pc`, display unspecified (null), provisional port 5900
/// - `lab-pc:1` → display 1, port 5901
/// - `lab-pc::5901` or `10.0.0.5::80` → raw TCP port (display null)
VncAddress parseVncAddress(String raw) {
  final s = raw.trim();
  if (s.isEmpty) {
    throw VncAddressParseException('empty address');
  }

  final doubleColon = s.indexOf('::');
  if (doubleColon >= 0) {
    final host = s.substring(0, doubleColon).trim();
    final portStr = s.substring(doubleColon + 2).trim();
    if (host.isEmpty) {
      throw VncAddressParseException('missing host');
    }
    final port = int.tryParse(portStr);
    if (port == null || port < 1 || port > 65535) {
      throw VncAddressParseException('invalid port');
    }
    return VncAddress(host: host, port: port);
  }

  // IPv6 in brackets: [fe80::1]:1 or [fe80::1]::5900 handled above for ::port
  // after brackets — skip for MVP; treat last single colon as display.
  final colon = _lastUnbracketedColon(s);
  if (colon < 0) {
    // Bare host: display unspecified so profile default_display can apply.
    return VncAddress(host: s, port: 5900);
  }

  final host = s.substring(0, colon).trim();
  final displayStr = s.substring(colon + 1).trim();
  if (host.isEmpty) {
    throw VncAddressParseException('missing host');
  }
  final display = int.tryParse(displayStr);
  if (display == null || display < 0 || display > 99) {
    throw VncAddressParseException('invalid display number');
  }
  final port = 5900 + display;
  if (port > 65535) {
    throw VncAddressParseException('port out of range');
  }
  return VncAddress(host: host, port: port, displayNumber: display);
}

int _lastUnbracketedColon(String s) {
  var depth = 0;
  var last = -1;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == '[') depth++;
    if (c == ']') depth = depth > 0 ? depth - 1 : 0;
    if (c == ':' && depth == 0) last = i;
  }
  return last;
}

VncAddress? tryParseVncAddress(String raw) {
  try {
    return parseVncAddress(raw);
  } on VncAddressParseException {
    return null;
  }
}
