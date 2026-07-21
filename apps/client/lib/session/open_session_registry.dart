/// Which UI shell hosts a live session.
enum SessionShell { windows, tabs }

extension SessionShellX on SessionShell {
  String get prefsKey => this == SessionShell.tabs ? 'tabs' : 'windows';

  static SessionShell fromPrefs(String? v) {
    switch (v) {
      case 'tabs':
        return SessionShell.tabs;
      default:
        return SessionShell.windows;
    }
  }
}

/// Open session tracked across window and tab shells.
class OpenSessionRef {
  const OpenSessionRef({
    required this.id,
    required this.host,
    required this.port,
    this.shell = SessionShell.windows,
    this.windowId,
    this.grabbed = true,
    this.profileId,
  });

  final int id;
  final String host;
  final int port;
  final SessionShell shell;
  final int? windowId;
  final bool grabbed;
  final String? profileId;

  String get key => '$host:$port';

  OpenSessionRef copyWith({
    int? id,
    String? host,
    int? port,
    SessionShell? shell,
    int? windowId,
    bool? grabbed,
    String? profileId,
    bool clearWindowId = false,
  }) {
    return OpenSessionRef(
      id: id ?? this.id,
      host: host ?? this.host,
      port: port ?? this.port,
      shell: shell ?? this.shell,
      windowId: clearWindowId ? null : (windowId ?? this.windowId),
      grabbed: grabbed ?? this.grabbed,
      profileId: profileId ?? this.profileId,
    );
  }
}

/// Single source of truth for open sessions (windows + tabs).
class OpenSessionRegistry {
  final _items = <OpenSessionRef>[];

  List<OpenSessionRef> get items => List.unmodifiable(_items);

  int get length => _items.length;

  bool get isEmpty => _items.isEmpty;

  OpenSessionRef? findByHostPort(String host, int port) {
    final want = '${host.trim()}:$port';
    for (final s in _items) {
      if ('${s.host.trim()}:${s.port}' == want) return s;
    }
    return null;
  }

  OpenSessionRef? findBySessionId(int sessionId) {
    for (final s in _items) {
      if (s.id == sessionId) return s;
    }
    return null;
  }

  void add(OpenSessionRef ref) {
    final existing = findByHostPort(ref.host, ref.port);
    if (existing != null) {
      final i = _items.indexWhere((s) => s.id == existing.id);
      if (i >= 0) _items[i] = ref;
      return;
    }
    _items.add(ref);
  }

  bool removeBySessionId(int sessionId) {
    final before = _items.length;
    _items.removeWhere((s) => s.id == sessionId);
    return _items.length != before;
  }

  bool replaceSessionId({
    required int oldId,
    required int newId,
    String? host,
    int? port,
  }) {
    for (var i = 0; i < _items.length; i++) {
      final s = _items[i];
      if (s.id != oldId) continue;
      _items[i] = s.copyWith(
        id: newId,
        host: host,
        port: port,
      );
      return true;
    }
    return false;
  }

  /// Detach a tabbed session to a window shell (registry only).
  bool detachToWindow(int sessionId, {int? windowId}) {
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].id != sessionId) continue;
      _items[i] = _items[i].copyWith(
        shell: SessionShell.windows,
        windowId: windowId,
      );
      return true;
    }
    return false;
  }

  /// Attach a windowed session into the tab shell.
  bool attachToTabs(int sessionId) {
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].id != sessionId) continue;
      _items[i] = _items[i].copyWith(
        shell: SessionShell.tabs,
        clearWindowId: true,
      );
      return true;
    }
    return false;
  }

  /// On tab switch: release grab on all, grab [activeId] if [wantGrab].
  void applyTabGrabPolicy({required int? activeId, bool wantGrab = true}) {
    for (var i = 0; i < _items.length; i++) {
      final s = _items[i];
      if (s.shell != SessionShell.tabs) continue;
      final shouldGrab = wantGrab && activeId != null && s.id == activeId;
      _items[i] = s.copyWith(grabbed: shouldGrab);
    }
  }

  List<OpenSessionRef> get tabSessions =>
      _items.where((s) => s.shell == SessionShell.tabs).toList();

  List<OpenSessionRef> get windowSessions =>
      _items.where((s) => s.shell == SessionShell.windows).toList();

  void clear() => _items.clear();
}

/// Routes new connects to window or tab shell based on preference.
class SessionShellRouter {
  const SessionShellRouter({required this.preferred});

  final SessionShell preferred;

  /// Shell to use for a new session. If [existing] is set, keep its shell.
  SessionShell routeForNew({OpenSessionRef? existing}) {
    if (existing != null) return existing.shell;
    return preferred;
  }

  /// Migrate all entries to [target] shell (registry metadata only).
  static void migrateAll(OpenSessionRegistry registry, SessionShell target) {
    final copy = List<OpenSessionRef>.from(registry.items);
    registry.clear();
    for (final s in copy) {
      registry.add(
        s.copyWith(
          shell: target,
          clearWindowId: target == SessionShell.tabs,
        ),
      );
    }
  }
}

// Backward-compatible free functions used by existing tests / hub.

OpenSessionRef? findOpenByHostPort(
  Iterable<OpenSessionRef> sessions,
  String host,
  int port,
) {
  final want = '${host.trim()}:$port';
  for (final s in sessions) {
    if ('${s.host.trim()}:${s.port}' == want) return s;
  }
  return null;
}

bool removeOpenBySessionId(List<OpenSessionRef> sessions, int sessionId) {
  final before = sessions.length;
  sessions.removeWhere((s) => s.id == sessionId);
  return sessions.length != before;
}

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
    sessions[i] = s.copyWith(id: newId, host: host, port: port);
    return true;
  }
  return false;
}
