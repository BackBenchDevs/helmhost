// Pure helpers for Hub session dedup / keys / library (unit-testable).

import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'library/vnc_address.dart';
import 'session/bandwidth_preset.dart';

export 'session/open_session_registry.dart';
export 'session/bandwidth_preset.dart';

String sessionKey(String host, int port) => '$host:$port';

int portFromDisplay(int display) => 5900 + display;

int? displayFromPort(int port) {
  if (port >= 5900 && port <= 5999) return port - 5900;
  return null;
}

/// Short hostname (before first `.`), Title Case each `-` segment.
///
/// `grog.bec.example` → `Grog`; `my-lab` → `My-Lab`.
String displayNameFromHost(String host) {
  final short = host.trim().split('.').first;
  if (short.isEmpty) return host.trim();
  return short.split('-').map((p) {
    if (p.isEmpty) return p;
    return '${p[0].toUpperCase()}${p.substring(1).toLowerCase()}';
  }).join('-');
}

/// Explicit [displayName] if non-empty; otherwise [displayNameFromHost].
String effectiveDisplayName({String? displayName, required String host}) {
  final d = displayName?.trim();
  if (d != null && d.isNotEmpty) return d;
  return displayNameFromHost(host);
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
    this.profileId,
    this.profileNone = false,
    this.openSessionId,
    this.bandwidthPreset = BandwidthPreset.balanced,
    this.qualityLevel,
    this.compressLevel,
    this.favorite = false,
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
  final String? profileId;
  final bool profileNone;
  final int? openSessionId;
  final BandwidthPreset bandwidthPreset;
  final int? qualityLevel;
  final int? compressLevel;
  final bool favorite;

  String get title =>
      effectiveDisplayName(displayName: displayName, host: host);

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
      profileId: j['profile_id'] as String?,
      profileNone: j['profile_none'] as bool? ?? false,
      openSessionId: openSessionId,
      bandwidthPreset:
          BandwidthPresetX.fromPrefs(j['bandwidth_preset'] as String?),
      qualityLevel: (j['quality_level'] as num?)?.toInt(),
      compressLevel: (j['compress_level'] as num?)?.toInt(),
      favorite: j['favorite'] as bool? ?? false,
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
        if (profileId != null) 'profile_id': profileId,
        'profile_none': profileNone,
        'bandwidth_preset': bandwidthPreset.prefsKey,
        if (qualityLevel != null) 'quality_level': qualityLevel,
        if (compressLevel != null) 'compress_level': compressLevel,
        'favorite': favorite,
      };

  LibraryCard copyWith({
    String? id,
    String? host,
    int? port,
    String? displayName,
    int? displayNumber,
    List<String>? tags,
    int? lastConnectedAt,
    String? thumbPath,
    String? username,
    bool? preferVencrypt,
    bool? acceptInvalidCerts,
    bool? viewOnly,
    String? notes,
    String? profileId,
    bool? profileNone,
    int? openSessionId,
    BandwidthPreset? bandwidthPreset,
    int? qualityLevel,
    int? compressLevel,
    bool? favorite,
  }) =>
      LibraryCard(
        id: id ?? this.id,
        host: host ?? this.host,
        port: port ?? this.port,
        displayName: displayName ?? this.displayName,
        displayNumber: displayNumber ?? this.displayNumber,
        tags: tags ?? this.tags,
        lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
        thumbPath: thumbPath ?? this.thumbPath,
        username: username ?? this.username,
        preferVencrypt: preferVencrypt ?? this.preferVencrypt,
        acceptInvalidCerts: acceptInvalidCerts ?? this.acceptInvalidCerts,
        viewOnly: viewOnly ?? this.viewOnly,
        notes: notes ?? this.notes,
        profileId: profileId ?? this.profileId,
        profileNone: profileNone ?? this.profileNone,
        openSessionId: openSessionId ?? this.openSessionId,
        bandwidthPreset: bandwidthPreset ?? this.bandwidthPreset,
        qualityLevel: qualityLevel ?? this.qualityLevel,
        compressLevel: compressLevel ?? this.compressLevel,
        favorite: favorite ?? this.favorite,
      );

  String get searchHaystack => [
        title,
        host,
        id,
        '$port',
        displayNumber?.toString() ?? '',
        tags.join(' '),
        username ?? '',
        notes ?? '',
        profileId ?? '',
      ].join('\n');
}

/// Local connection profile (mirrors Rust ConnectionProfile).
class ConnectionProfileCard {
  const ConnectionProfileCard({
    required this.id,
    required this.name,
    this.domain = '',
    this.notes,
    this.preferVencrypt = false,
    this.acceptInvalidCerts = false,
    this.viewOnly = false,
    this.defaultUsername,
    this.defaultDisplay,
  });

  final String id;
  final String name;
  final String domain;
  final String? notes;
  final bool preferVencrypt;
  final bool acceptInvalidCerts;
  final bool viewOnly;
  final String? defaultUsername;
  final int? defaultDisplay;

  String get domainLabel {
    final d = normalizeDomain(domain);
    return d.isEmpty ? name : '*.$d';
  }

  factory ConnectionProfileCard.fromJson(Map<String, dynamic> j) {
    List<String> strList(dynamic v) => v is List
        ? v.map((e) => e.toString()).toList()
        : <String>[];
    var domain = (j['domain'] as String?)?.trim() ?? '';
    if (domain.isEmpty) {
      final search = strList(j['dns_search']);
      if (search.isNotEmpty) domain = search.first;
    }
    return ConnectionProfileCard(
      id: j['id'] as String? ?? '',
      name: j['name'] as String? ?? '',
      domain: normalizeDomain(domain),
      notes: j['notes'] as String?,
      preferVencrypt: j['prefer_vencrypt'] as bool? ?? false,
      acceptInvalidCerts: j['accept_invalid_certs'] as bool? ?? false,
      viewOnly: j['view_only'] as bool? ?? false,
      defaultUsername: j['default_username'] as String?,
      defaultDisplay: (j['default_display'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'domain': normalizeDomain(domain),
        if (notes != null) 'notes': notes,
        'prefer_vencrypt': preferVencrypt,
        'accept_invalid_certs': acceptInvalidCerts,
        'view_only': viewOnly,
        if (defaultUsername != null) 'default_username': defaultUsername,
        // Always emit so FFI/serde never treat "omit" as an accidental clear
        // when merging is wrong — upsert replaces the whole profile.
        'default_display': defaultDisplay,
      };
}

/// Parse default display from profile editor text (empty → null).
int? parseDefaultDisplayField(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  // Allow accidental spaces / unicode; keep ASCII digits only.
  final digits = t.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  final n = int.tryParse(digits);
  if (n == null || n < 0 || n > 99) return null;
  return n;
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
  /// Local paint only. Remote FB size always follows the window (SetDesktopSize),
  /// except while the Library overlay is open or settling after collapse.
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
      case 'oneToOne': // legacy → Fill window
        return ViewScaleMode.fill;
      default:
        return ViewScaleMode.fit;
    }
  }

  /// Local paint transform. Both modes use contain until remote size matches
  /// (never stretch). Remote resize is independent of this preference.
  BoxFit get boxFit {
    switch (this) {
      case ViewScaleMode.fit:
      case ViewScaleMode.fill:
        return BoxFit.contain;
    }
  }

  /// Short status-menu description (remote size follows the window either way).
  String get menuHint {
    switch (this) {
      case ViewScaleMode.fit:
        return 'letterbox locally until FB matches';
      case ViewScaleMode.fill:
        return 'prefer matched remote size (no stretch)';
    }
  }

  /// Deprecated for resize gating — remote resize always follows window size.
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

enum LibraryGridSize { small, medium, large }

extension LibraryGridSizeX on LibraryGridSize {
  double get maxCrossAxisExtent => switch (this) {
        LibraryGridSize.small => 200,
        LibraryGridSize.medium => 260,
        LibraryGridSize.large => 340,
      };

  String get label => switch (this) {
        LibraryGridSize.small => 'Small',
        LibraryGridSize.medium => 'Medium',
        LibraryGridSize.large => 'Large',
      };

  LibraryGridSize get next => switch (this) {
        LibraryGridSize.small => LibraryGridSize.medium,
        LibraryGridSize.medium => LibraryGridSize.large,
        LibraryGridSize.large => LibraryGridSize.small,
      };
}

// ---------------------------------------------------------------------------
// Library sort
// ---------------------------------------------------------------------------

enum LibrarySort { name, host, lastConnected, openFirst }

extension LibrarySortX on LibrarySort {
  String get label => switch (this) {
        LibrarySort.name => 'Name',
        LibrarySort.host => 'Host',
        LibrarySort.lastConnected => 'Last connected',
        LibrarySort.openFirst => 'Open first',
      };

  String get prefsKey => switch (this) {
        LibrarySort.name => 'name',
        LibrarySort.host => 'host',
        LibrarySort.lastConnected => 'last_connected',
        LibrarySort.openFirst => 'open_first',
      };

  LibrarySort get next => switch (this) {
        LibrarySort.name => LibrarySort.host,
        LibrarySort.host => LibrarySort.lastConnected,
        LibrarySort.lastConnected => LibrarySort.openFirst,
        LibrarySort.openFirst => LibrarySort.name,
      };

  static LibrarySort fromPrefs(String? v) => switch (v) {
        'host' => LibrarySort.host,
        'last_connected' => LibrarySort.lastConnected,
        'open_first' => LibrarySort.openFirst,
        _ => LibrarySort.name,
      };
}

List<LibraryCard> sortLibraryCards(
  Iterable<LibraryCard> cards,
  LibrarySort sort, {
  bool favoritesFirst = true,
}) {
  final list = cards.toList();
  list.sort((a, b) {
    if (favoritesFirst) {
      final fav = (b.favorite ? 1 : 0) - (a.favorite ? 1 : 0);
      if (fav != 0) return fav;
    }
    switch (sort) {
      case LibrarySort.name:
        return a.title.compareTo(b.title);
      case LibrarySort.host:
        final h = a.host.compareTo(b.host);
        return h != 0 ? h : a.port.compareTo(b.port);
      case LibrarySort.lastConnected:
        final at = b.lastConnectedAt ?? -1;
        final bt = a.lastConnectedAt ?? -1;
        return at.compareTo(bt);
      case LibrarySort.openFirst:
        final o = (b.isOpen ? 1 : 0) - (a.isOpen ? 1 : 0);
        return o != 0 ? o : a.title.compareTo(b.title);
    }
  });
  return list;
}

/// Collect all unique tags from [cards], sorted alphabetically.
List<String> collectLibraryTags(Iterable<LibraryCard> cards) {
  final seen = <String>{};
  final result = <String>[];
  for (final c in cards) {
    for (final t in c.tags) {
      if (seen.add(t)) result.add(t);
    }
  }
  result.sort();
  return result;
}

List<LibraryCard> filterLibraryCardsByTag(
  Iterable<LibraryCard> cards,
  String tag,
) =>
    cards.where((c) => c.tags.contains(tag)).toList();

// ---------------------------------------------------------------------------
// Thumb refresh rate
// ---------------------------------------------------------------------------

enum LibraryThumbRefresh { off, slow, normal }

extension LibraryThumbRefreshX on LibraryThumbRefresh {
  String get prefsKey => switch (this) {
        LibraryThumbRefresh.off => 'off',
        LibraryThumbRefresh.slow => 'slow',
        LibraryThumbRefresh.normal => 'normal',
      };

  String get label => switch (this) {
        LibraryThumbRefresh.off => 'Off',
        LibraryThumbRefresh.slow => 'Slow (5 s)',
        LibraryThumbRefresh.normal => 'Normal (1 s)',
      };

  LibraryThumbRefresh get next => switch (this) {
        LibraryThumbRefresh.off => LibraryThumbRefresh.slow,
        LibraryThumbRefresh.slow => LibraryThumbRefresh.normal,
        LibraryThumbRefresh.normal => LibraryThumbRefresh.off,
      };

  /// Null when off; otherwise the poll interval in milliseconds.
  int? get thumbRefreshIntervalMs => switch (this) {
        LibraryThumbRefresh.off => null,
        LibraryThumbRefresh.slow => 5000,
        LibraryThumbRefresh.normal => 1000,
      };

  static LibraryThumbRefresh fromPrefs(String? v) => switch (v) {
        'off' => LibraryThumbRefresh.off,
        'slow' => LibraryThumbRefresh.slow,
        _ => LibraryThumbRefresh.normal,
      };
}

// ---------------------------------------------------------------------------
// Grid layout helpers
// ---------------------------------------------------------------------------

EdgeInsets libraryGridFooterPadding(LibraryGridSize size) =>
    size == LibraryGridSize.small
        ? const EdgeInsets.fromLTRB(6, 4, 6, 4)
        : const EdgeInsets.fromLTRB(8, 6, 8, 6);

TextStyle libraryGridTitleStyle(LibraryGridSize size) => TextStyle(
      fontSize: size == LibraryGridSize.small ? 11.5 : 13.0,
      fontWeight: FontWeight.w500,
    );

/// Clamp a custom grid extent to [160, 400], or null if [extent] is null.
double? clampLibraryGridExtent(double? extent) =>
    extent?.clamp(160.0, 400.0);

/// Effective max cross-axis extent: clamped [extent] if set, else [size] default.
double effectiveMaxCrossAxisExtent({
  required LibraryGridSize size,
  double? extent,
}) =>
    clampLibraryGridExtent(extent) ?? size.maxCrossAxisExtent;

String normalizeDomain(String domain) => domain
    .trim()
    .replaceFirst(RegExp(r'^\.+'), '')
    .replaceFirst(RegExp(r'\.+$'), '')
    .toLowerCase();

bool hostMatchesDomain(String host, String domain) {
  final h = host.trim().toLowerCase();
  final d = normalizeDomain(domain);
  if (h.isEmpty || d.isEmpty) return false;
  return h == d || h.endsWith('.$d');
}

List<String> _dnsLabels(String value) => normalizeDomain(value)
    .split('.')
    .where((p) => p.isNotEmpty)
    .toList();

/// When [host] ends with a *proper prefix* of [domain], return the local
/// labels before that prefix (may be empty if host is only the prefix).
///
/// `ava1.bec` + `bec.broadcom.net` → `ava1`
/// `ava1.bec.broadcom` + `bec.broadcom.net` → `ava1`
/// Full-domain hosts return null (use [hostMatchesDomain] / [shortHost]).
String? partialDomainLocalHost(String host, String domain) {
  final hLabels = _dnsLabels(host);
  final dLabels = _dnsLabels(domain);
  if (hLabels.length < 2 || dLabels.length < 2) return null;
  if (hostMatchesDomain(host, domain)) return null;

  // Largest N where host suffix == domain prefix and N < domain length.
  var bestN = 0;
  final maxN = hLabels.length < dLabels.length
      ? hLabels.length
      : dLabels.length - 1;
  for (var n = 1; n <= maxN; n++) {
    final hostSuffix = hLabels.sublist(hLabels.length - n);
    final domainPrefix = dLabels.sublist(0, n);
    if (_labelsEqual(hostSuffix, domainPrefix)) bestN = n;
  }
  if (bestN == 0) return null;
  final local = hLabels.sublist(0, hLabels.length - bestN);
  return local.join('.');
}

bool _labelsEqual(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Expand partial host under [domain], or null if not a partial match.
///
/// `ava1.bec` + `bec.broadcom.net` → `ava1.bec.broadcom.net`
String? expandPartialHost(String host, String domain) {
  final local = partialDomainLocalHost(host, domain);
  if (local == null) return null;
  final d = normalizeDomain(domain);
  if (local.isEmpty) return d;
  return '$local.$d';
}

bool hostPartiallyMatchesDomain(String host, String domain) =>
    expandPartialHost(host, domain) != null;

String shortHost(String host, String domain) {
  final h = host.trim();
  final d = normalizeDomain(domain);
  if (d.isEmpty) return h;
  final lower = h.toLowerCase();
  final suffix = '.$d';
  if (lower.endsWith(suffix)) return h.substring(0, h.length - suffix.length);
  if (lower == d) return '';
  final partialLocal = partialDomainLocalHost(h, d);
  if (partialLocal != null) return partialLocal;
  return h;
}

/// Qualify short hostname with domain (mirrors Rust `qualify_host`).
String qualifyHost(String host, String domain) {
  final h = host.trim();
  final d = normalizeDomain(domain);
  if (h.isEmpty || d.isEmpty) return h;
  if (hostMatchesDomain(h, d)) {
    final s = shortHost(h, d);
    if (s.isEmpty) return d;
    return '$s.$d';
  }
  if (!h.contains('.')) return '$h.$d';
  final expanded = expandPartialHost(h, d);
  if (expanded != null) return expanded;
  return h;
}

String profileVaultKey(String profileId) => 'profile:$profileId';

bool cardMatchesProfile(LibraryCard card, ConnectionProfileCard profile) {
  if (card.profileNone) return false;
  if (card.profileId != null) return card.profileId == profile.id;
  final d = normalizeDomain(profile.domain);
  if (d.isEmpty) return false;
  return hostMatchesDomain(card.host, d) ||
      hostMatchesDomain(qualifyHost(card.host, d), d);
}

/// Next UI step after [resolveQuickConnect] / [resolveNewConnectionHost].
enum QuickConnectIntent {
  /// Profile known (sidebar filter / named group) — connect without prompt.
  ready,
  /// New host matched/qualified to a group — confirm Add to group.
  confirmAddToGroup,
  /// Need user to pick a group (short host with 2+ domains, or unmatched FQDN).
  needGroupPick,
  /// No profiles with a Domain — offer Create profile.
  needCreateProfile,
}

/// Result of resolving an address-bar quick-connect string.
class QuickConnectTarget {
  const QuickConnectTarget({
    required this.connectHost,
    required this.port,
    this.displayNumber,
    this.profileId,
    required this.entryHost,
    this.intent = QuickConnectIntent.ready,
  });

  final String connectHost;
  final int port;
  final int? displayNumber;
  final String? profileId;
  final String entryHost;
  final QuickConnectIntent intent;

  /// True when Auto assigned a group and UI should confirm before filing.
  bool get autoAssignedProfile =>
      intent == QuickConnectIntent.confirmAddToGroup;
}

class QuickConnectResult {
  const QuickConnectResult.ok(this.target) : error = null;
  const QuickConnectResult.fail(this.error) : target = null;

  final QuickConnectTarget? target;
  final String? error;
}

List<ConnectionProfileCard> profilesWithDomain(
  List<ConnectionProfileCard> profiles,
) =>
    profiles.where((p) => normalizeDomain(p.domain).isNotEmpty).toList();

QuickConnectTarget _finishQuickConnectTarget({
  required String host,
  required int preliminaryPort,
  required int? preliminaryDisplay,
  required bool displayOmitted,
  required ConnectionProfileCard? activeProfile,
  required String? profileId,
  required QuickConnectIntent intent,
}) {
  var port = preliminaryPort;
  int? displayNumber = preliminaryDisplay;

  if (displayOmitted) {
    final def = activeProfile?.defaultDisplay;
    if (def != null) {
      displayNumber = def;
      port = portFromDisplay(def);
    }
  }

  var entryHost = host;
  if (activeProfile != null &&
      normalizeDomain(activeProfile.domain).isNotEmpty) {
    final short = shortHost(host, activeProfile.domain);
    entryHost = short.isEmpty ? host : short;
  }

  return QuickConnectTarget(
    connectHost: host,
    port: port,
    displayNumber: displayNumber,
    profileId: profileId,
    entryHost: entryHost,
    intent: intent,
  );
}

/// Qualify short hosts, apply profile [defaultDisplay] when display omitted.
QuickConnectResult resolveQuickConnect({
  required String rawInput,
  required List<ConnectionProfileCard> profiles,
  String? filterProfileId,
}) {
  final raw = rawInput.trim();
  if (raw.isEmpty) {
    return const QuickConnectResult.fail('Enter a host or VNC address');
  }

  final preliminary = tryParseVncAddress(raw);
  if (preliminary == null) {
    return const QuickConnectResult.fail('Invalid VNC address');
  }

  final hadRawPort = raw.contains('::');
  final displayOmitted =
      preliminary.displayNumber == null && !hadRawPort;

  ConnectionProfileCard? filterProfile;
  if (filterProfileId != null) {
    for (final p in profiles) {
      if (p.id == filterProfileId) {
        filterProfile = p;
        break;
      }
    }
  }

  var host = preliminary.host;
  final hostIsShort = !host.contains('.');
  final withDomain = profilesWithDomain(profiles);

  String? profileId = filterProfile?.id;
  ConnectionProfileCard? activeProfile = filterProfile;
  var intent = QuickConnectIntent.ready;

  if (hostIsShort) {
    if (filterProfile != null &&
        normalizeDomain(filterProfile.domain).isEmpty) {
      return QuickConnectResult.fail(
        '“${filterProfile.name}” has no domain — edit the profile and set Domain',
      );
    }
    var qualifyWith = filterProfile;
    if (qualifyWith == null) {
      if (withDomain.isEmpty) {
        return QuickConnectResult.ok(
          QuickConnectTarget(
            connectHost: host,
            port: preliminary.port,
            displayNumber: displayOmitted ? null : preliminary.displayNumber,
            entryHost: host,
            intent: QuickConnectIntent.needCreateProfile,
          ),
        );
      }
      if (withDomain.length > 1) {
        return QuickConnectResult.ok(
          QuickConnectTarget(
            connectHost: host,
            port: preliminary.port,
            displayNumber: displayOmitted ? null : preliminary.displayNumber,
            entryHost: host,
            intent: QuickConnectIntent.needGroupPick,
          ),
        );
      }
      qualifyWith = withDomain.first;
      intent = QuickConnectIntent.confirmAddToGroup;
    }
    if (normalizeDomain(qualifyWith.domain).isEmpty) {
      return QuickConnectResult.fail(
        '“${qualifyWith.name}” has no domain — edit the profile and set Domain',
      );
    }
    profileId = qualifyWith.id;
    activeProfile = qualifyWith;
    host = qualifyHost(host, qualifyWith.domain);
  } else if (filterProfile == null) {
    ConnectionProfileCard? matched;
    for (final p in withDomain) {
      if (hostMatchesDomain(host, p.domain)) {
        matched = p;
        break; // first full match wins
      }
    }
    if (matched != null) {
      profileId = matched.id;
      activeProfile = matched;
      intent = QuickConnectIntent.confirmAddToGroup;
    } else {
      final partials = withDomain
          .where((p) => hostPartiallyMatchesDomain(host, p.domain))
          .toList();
      if (partials.length == 1) {
        matched = partials.first;
        host = expandPartialHost(host, matched.domain)!;
        profileId = matched.id;
        activeProfile = matched;
        intent = QuickConnectIntent.confirmAddToGroup;
      } else if (partials.length > 1) {
        return QuickConnectResult.ok(
          QuickConnectTarget(
            connectHost: host,
            port: preliminary.port,
            displayNumber: displayOmitted ? null : preliminary.displayNumber,
            entryHost: host,
            intent: QuickConnectIntent.needGroupPick,
          ),
        );
      } else if (withDomain.isEmpty) {
        return QuickConnectResult.ok(
          QuickConnectTarget(
            connectHost: host,
            port: preliminary.port,
            displayNumber: displayOmitted ? null : preliminary.displayNumber,
            entryHost: host,
            intent: QuickConnectIntent.needCreateProfile,
          ),
        );
      } else {
        return QuickConnectResult.ok(
          QuickConnectTarget(
            connectHost: host,
            port: preliminary.port,
            displayNumber: displayOmitted ? null : preliminary.displayNumber,
            entryHost: host,
            intent: QuickConnectIntent.needGroupPick,
          ),
        );
      }
    }
  } else {
    // Sidebar / named filter: expand partial or keep FQDN as typed.
    final d = normalizeDomain(filterProfile.domain);
    if (d.isNotEmpty) {
      if (hostMatchesDomain(host, d)) {
        activeProfile = filterProfile;
      } else {
        final expanded = expandPartialHost(host, d);
        if (expanded != null) {
          host = expanded;
          activeProfile = filterProfile;
        }
      }
    }
  }

  return QuickConnectResult.ok(
    _finishQuickConnectTarget(
      host: host,
      preliminaryPort: preliminary.port,
      preliminaryDisplay: preliminary.displayNumber,
      displayOmitted: displayOmitted,
      activeProfile: activeProfile,
      profileId: profileId,
      intent: intent,
    ),
  );
}

/// New Connection dialog resolve: [profileKey] null=Auto, `__none__`=None, else id.
QuickConnectResult resolveNewConnectionHost({
  required String rawInput,
  required List<ConnectionProfileCard> profiles,
  String? profileKey,
}) {
  if (profileKey == '__none__') {
    final raw = rawInput.trim();
    if (raw.isEmpty) {
      return const QuickConnectResult.fail('Enter a host or VNC address');
    }
    final preliminary = tryParseVncAddress(raw);
    if (preliminary == null) {
      return const QuickConnectResult.fail('Invalid VNC address');
    }
    if (!preliminary.host.contains('.')) {
      return const QuickConnectResult.fail(
        'Choose a group with a Domain, or type a full hostname',
      );
    }
    final hadRawPort = raw.contains('::');
    final displayOmitted =
        preliminary.displayNumber == null && !hadRawPort;
    return QuickConnectResult.ok(
      QuickConnectTarget(
        connectHost: preliminary.host,
        port: preliminary.port,
        displayNumber: displayOmitted ? null : preliminary.displayNumber,
        profileId: null,
        entryHost: preliminary.host,
        intent: QuickConnectIntent.ready,
      ),
    );
  }

  return resolveQuickConnect(
    rawInput: rawInput,
    profiles: profiles,
    filterProfileId: profileKey,
  );
}

/// Suggest editable group Name from Domain (`bec.broadcom.net` → `bec.broadcom`).
String suggestProfileNameFromDomain(String domain) {
  var d = normalizeDomain(domain);
  if (d.startsWith('www.')) d = d.substring(4);
  if (d.isEmpty) return '';
  final parts = d.split('.')..removeWhere((p) => p.isEmpty);
  if (parts.length >= 3) {
    return parts.sublist(0, parts.length - 1).join('.');
  }
  return d;
}

/// Find a library card that already represents [connectHost]:[port].
LibraryCard? findDuplicateLibraryCard({
  required Iterable<LibraryCard> cards,
  required String connectHost,
  required int port,
  required List<ConnectionProfileCard> profiles,
}) {
  final want = sessionKey(connectHost.trim().toLowerCase(), port);
  for (final c in cards) {
    final keys = <String>{
      c.id.toLowerCase(),
      sessionKey(c.host.trim().toLowerCase(), c.port),
    };
    if (c.profileId != null) {
      for (final p in profiles) {
        if (p.id == c.profileId && normalizeDomain(p.domain).isNotEmpty) {
          keys.add(
            sessionKey(
              qualifyHost(c.host, p.domain).toLowerCase(),
              c.port,
            ),
          );
        }
      }
    } else if (!c.profileNone) {
      for (final p in profiles) {
        if (normalizeDomain(p.domain).isEmpty) continue;
        keys.add(
          sessionKey(qualifyHost(c.host, p.domain).toLowerCase(), c.port),
        );
      }
    }
    if (keys.contains(want)) return c;
  }
  return null;
}

/// Preview shown when Auto assigns a group (FQDN + name confirmation).
class AutoGroupAssignPreview {
  const AutoGroupAssignPreview({
    required this.groupName,
    required this.groupId,
    required this.connectHost,
    required this.entryHost,
    required this.suggestedName,
    required this.port,
  });

  final String groupName;
  final String groupId;
  final String connectHost;
  final String entryHost;
  final String suggestedName;
  final int port;
}

/// Build confirm preview when [target] should confirm Add to group.
AutoGroupAssignPreview? autoGroupAssignPreview({
  required QuickConnectTarget target,
  required List<ConnectionProfileCard> profiles,
  String? explicitDisplayName,
}) {
  if (target.intent != QuickConnectIntent.confirmAddToGroup ||
      target.profileId == null) {
    return null;
  }
  return groupAssignPreviewFor(
    target: target,
    profiles: profiles,
    explicitDisplayName: explicitDisplayName,
  );
}

/// Preview for a target that already has [QuickConnectTarget.profileId].
AutoGroupAssignPreview? groupAssignPreviewFor({
  required QuickConnectTarget target,
  required List<ConnectionProfileCard> profiles,
  String? explicitDisplayName,
}) {
  if (target.profileId == null) return null;
  ConnectionProfileCard? group;
  for (final p in profiles) {
    if (p.id == target.profileId) {
      group = p;
      break;
    }
  }
  if (group == null) return null;
  final name =
      (explicitDisplayName != null && explicitDisplayName.trim().isNotEmpty)
          ? explicitDisplayName.trim()
          : displayNameFromHost(target.entryHost);
  return AutoGroupAssignPreview(
    groupName: group.name,
    groupId: group.id,
    connectHost: target.connectHost,
    entryHost: target.entryHost,
    suggestedName: name,
    port: target.port,
  );
}

/// Reassign [existing] to the draft's profile without creating a second card.
Map<String, dynamic> mergeMovedDuplicateEntry({
  required LibraryCard existing,
  required Map<String, dynamic> draft,
}) {
  final wantNone = draft['profile_none'] == true;
  final wantProfileId = draft['profile_id'] as String?;
  return {
    ...existing.toJson(),
    ...draft,
    'id': existing.id,
    'host': existing.host,
    'port': existing.port,
    if (wantNone) 'profile_id': null,
    'profile_none': wantNone,
    if (!wantNone && wantProfileId != null) 'profile_id': wantProfileId,
  };
}

/// Connect port for a library card after registry resolve.
int connectPortForCard({
  required LibraryCard card,
  Map<String, dynamic>? resolved,
}) {
  if (card.displayNumber != null) return card.port;
  final resolvedDisplay = (resolved?['display_number'] as num?)?.toInt();
  if (resolvedDisplay != null) return portFromDisplay(resolvedDisplay);
  return card.port;
}

