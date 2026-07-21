// Pure helpers for Hub session dedup / keys / library (unit-testable).

import 'dart:convert';

import 'package:flutter/widgets.dart';

String sessionKey(String host, int port) => '$host:$port';

int portFromDisplay(int display) => 5900 + display;

int? displayFromPort(int port) {
  if (port >= 5900 && port <= 5999) return port - 5900;
  return null;
}

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

/// Remove open refs by session id. Returns true if anything was removed.
bool removeOpenBySessionId(List<OpenSessionRef> sessions, int sessionId) {
  final before = sessions.length;
  sessions.removeWhere((s) => s.id == sessionId);
  return sessions.length != before;
}

/// Replace an open session id (reconnect). Returns false if [oldId] missing.
bool replaceOpenSessionId(
  List<OpenSessionRef> sessions, {
  required int oldId,
  required int newId,
  String? host,
  int? port,
}) {
  for (var i = 0; i < sessions.length; i++) {
    final s = sessions[i];
    if (s.id != oldId) continue;
    sessions[i] = OpenSessionRef(
      id: newId,
      host: host ?? s.host,
      port: port ?? s.port,
    );
    return true;
  }
  return false;
}

/// Library card model (from registry JSON).
class LibraryCard {
  const LibraryCard({
    required this.id,
    required this.host,
    required this.port,
    this.displayName,
    this.displayNumber,
    this.tags = const [],
    this.lastConnectedAt,
    this.thumbPath,
    this.username,
    this.preferVencrypt = false,
    this.acceptInvalidCerts = false,
    this.viewOnly = false,
    this.notes,
    this.openSessionId,
  });

  final String id;
  final String host;
  final int port;
  final String? displayName;
  final int? displayNumber;
  final List<String> tags;
  final int? lastConnectedAt;
  final String? thumbPath;
  final String? username;
  final bool preferVencrypt;
  final bool acceptInvalidCerts;
  final bool viewOnly;
  final String? notes;
  final int? openSessionId;

  String get title =>
      (displayName != null && displayName!.isNotEmpty) ? displayName! : id;

  String get subtitle {
    final d = displayNumber ?? displayFromPort(port);
    if (d != null) return '$host :$d ($port)';
    return '$host:$port';
  }

  bool get isOpen => openSessionId != null;

  factory LibraryCard.fromJson(Map<String, dynamic> j, {int? openSessionId}) {
    final tagsRaw = j['tags'];
    final tags = tagsRaw is List
        ? tagsRaw.map((e) => e.toString()).toList()
        : <String>[];
    return LibraryCard(
      id: j['id'] as String? ?? '',
      host: j['host'] as String? ?? '',
      port: (j['port'] as num?)?.toInt() ?? 5900,
      displayName: j['display_name'] as String?,
      displayNumber: (j['display_number'] as num?)?.toInt(),
      tags: tags,
      lastConnectedAt: (j['last_connected_at'] as num?)?.toInt(),
      thumbPath: j['thumb_path'] as String?,
      username: j['username'] as String?,
      preferVencrypt: j['prefer_vencrypt'] as bool? ?? false,
      acceptInvalidCerts: j['accept_invalid_certs'] as bool? ?? false,
      viewOnly: j['view_only'] as bool? ?? false,
      notes: j['notes'] as String?,
      openSessionId: openSessionId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'host': host,
        'port': port,
        if (displayName != null) 'display_name': displayName,
        if (displayNumber != null) 'display_number': displayNumber,
        'tags': tags,
        if (lastConnectedAt != null) 'last_connected_at': lastConnectedAt,
        if (thumbPath != null) 'thumb_path': thumbPath,
        if (username != null) 'username': username,
        'prefer_vencrypt': preferVencrypt,
        'accept_invalid_certs': acceptInvalidCerts,
        'view_only': viewOnly,
        if (notes != null) 'notes': notes,
      };

  String get searchHaystack => [
        title,
        host,
        id,
        '$port',
        displayNumber?.toString() ?? '',
        tags.join(' '),
        username ?? '',
        notes ?? '',
      ].join('\n');
}

RegExp? tryParseSearchPattern(String query) {
  final q = query.trim();
  if (q.isEmpty) return null;
  try {
    return RegExp(q, caseSensitive: false);
  } catch (_) {
    return null;
  }
}

bool matchesRegex(LibraryCard card, RegExp? pattern) {
  if (pattern == null) return true;
  return pattern.hasMatch(card.searchHaystack);
}

List<LibraryCard> filterLibraryCardsRegex(
  Iterable<LibraryCard> cards,
  String query,
) {
  final pattern = tryParseSearchPattern(query);
  if (query.trim().isNotEmpty && pattern == null) return cards.toList();
  return cards.where((c) => matchesRegex(c, pattern)).toList();
}

String exportEntryJson(LibraryCard card) {
  return jsonEncode({'entries': {card.id: card.toJson()}});
}

String safeExportFilename(String id) =>
    'helmhost-${id.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}.json';

enum ViewScaleMode {
  fit,
  fill,
}

extension ViewScaleModeX on ViewScaleMode {
  /// Fit (aspect) = local letterbox only (TigerVNC FixedRatio / no RemoteResize).
  /// Fill window = TigerVNC RemoteResize: remote FB matches viewport; paint 1:1 (never stretch).
  String get label {
    switch (this) {
      case ViewScaleMode.fit:
        return 'Fit (aspect)';
      case ViewScaleMode.fill:
        return 'Fill window';
    }
  }

  String get prefsKey {
    switch (this) {
      case ViewScaleMode.fit:
        return 'fit';
      case ViewScaleMode.fill:
        return 'fill';
    }
  }

  static ViewScaleMode fromPrefs(String? v) {
    switch (v) {
      case 'fill':
      case 'oneToOne': // legacy → Fill window (RemoteResize)
        return ViewScaleMode.fill;
      default:
        return ViewScaleMode.fit;
    }
  }

  /// Local paint transform. Fill uses contain until remote size matches (never stretch).
  BoxFit get boxFit {
    switch (this) {
      case ViewScaleMode.fit:
      case ViewScaleMode.fill:
        return BoxFit.contain;
    }
  }

  bool get usesRemoteResize => this == ViewScaleMode.fill;
}

enum AuthNeed { none, password, usernamePassword }

AuthNeed parseAuthNeed(String error) {
  if (error.contains('NEED_USERNAME_PASSWORD')) {
    return AuthNeed.usernamePassword;
  }
  if (error.contains('NEED_PASSWORD')) return AuthNeed.password;
  return AuthNeed.none;
}

enum LibraryViewMode { grid, list }
