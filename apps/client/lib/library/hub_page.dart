import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../bridge.dart';
import '../logging/logger.dart';
import '../prefs.dart';
import '../session/credentials.dart';
import '../session/session_ipc.dart';
import '../session_helpers.dart';
import '../storage/app_paths.dart';
import '../storage/credential_store.dart';
import '../thumbs.dart';
import 'auth_dialog.dart';
import 'connection_editor.dart';
import 'library_card_widgets.dart';
import 'library_status_bar.dart';
import 'profile_editor.dart';
import 'tab_session_workspace.dart';
import 'vnc_address.dart';

extension WindowControllerExt on WindowController {
  Future<void> closeWindow() => invokeMethod(kMethodWindowClose);
}

class HubPage extends StatefulWidget {
  HubPage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.viewMode,
    required this.onViewModeChanged,
    required this.sessionShell,
    required this.onSessionShellChanged,
    this.prefs,
    ILogger? logger,
  }) : logger = logger ?? defaultLogger(module: 'hub');

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final LibraryViewMode viewMode;
  final ValueChanged<LibraryViewMode> onViewModeChanged;
  final SessionShell sessionShell;
  final ValueChanged<SessionShell> onSessionShellChanged;
  final AppPrefs? prefs;
  final ILogger logger;

  @override
  State<HubPage> createState() => _HubPageState();
}

class _HubPageState extends State<HubPage> with WindowListener {
  HelmBridge? _bridge;
  final ICredentialStore _credentials = createCredentialStore();
  String? _error;
  String _hello = '';
  List<LibraryCard> _cards = [];
  List<ConnectionProfileCard> _profiles = [];
  final _search = TextEditingController();
  final _sessions = OpenSessionRegistry();
  bool _connecting = false;
  String? _thumbsRoot;
  final _liveThumbs = <String, Uint8List>{};
  Timer? _liveTimer;
  String? _searchPatternError;
  String? _profileFilterId; // null = all
  int? _activeTabSessionId;
  var _libraryTabSelected = true;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
    _search.addListener(_onSearchChanged);
    _liveTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshLiveThumbs(),
    );
    unawaited(_registerIpc());
    _boot();
  }

  Future<void> _registerIpc() async {
    final c = await WindowController.fromCurrentEngine();
    await c.setWindowMethodHandler((call) async {
      switch (call.method) {
        case kMethodWindowClose:
          await windowManager.close();
          return null;
        case kMethodSessionEnded:
          _onSessionEnded(call.arguments);
          return null;
        case kMethodSessionReplaced:
          _onSessionReplaced(call.arguments);
          return null;
        default:
          throw MissingPluginException(call.method);
      }
    });
  }

  void _onSessionEnded(dynamic raw) {
    final args = _asArgMap(raw);
    final id = (args['sessionId'] as num?)?.toInt();
    if (id == null) return;
    if (!_sessions.removeBySessionId(id)) return;
    if (_activeTabSessionId == id) {
      _activeTabSessionId = _sessions.tabSessions.isEmpty
          ? null
          : _sessions.tabSessions.last.id;
      _libraryTabSelected = _activeTabSessionId == null;
    }
    if (!mounted) return;
    setState(_reloadCards);
  }

  void _onSessionReplaced(dynamic raw) {
    final args = _asArgMap(raw);
    final oldId = (args['oldId'] as num?)?.toInt();
    final newId = (args['newId'] as num?)?.toInt();
    if (oldId == null || newId == null) return;
    final host = args['host'] as String?;
    final port = (args['port'] as num?)?.toInt();
    final ok = _sessions.replaceSessionId(
      oldId: oldId,
      newId: newId,
      host: host,
      port: port,
    );
    if (!ok && host != null && port != null) {
      _sessions.add(OpenSessionRef(
        id: newId,
        host: host,
        port: port,
        shell: widget.sessionShell,
      ));
    }
    if (_activeTabSessionId == oldId) _activeTabSessionId = newId;
    if (!mounted) return;
    setState(_reloadCards);
  }

  Map<String, dynamic> _asArgMap(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return {};
  }

  void _onSearchChanged() {
    final q = _search.text.trim();
    if (q.isEmpty) {
      setState(() => _searchPatternError = null);
      return;
    }
    // Address-like input is fine for filter + Connect; only flag bad regex
    // when it isn't a plausible VNC address.
    if (tryParseVncAddress(q) != null) {
      setState(() => _searchPatternError = null);
      return;
    }
    setState(() {
      _searchPatternError =
          tryParseSearchPattern(q) == null ? 'Invalid regex pattern' : null;
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _liveTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() async {
    for (final s in List<OpenSessionRef>.from(_sessions.items)) {
      try {
        _bridge?.close(s.id);
      } catch (_) {}
      try {
        for (final c in await WindowController.getAll()) {
          if (c.arguments.isEmpty) continue;
          final a = jsonDecode(c.arguments) as Map<String, dynamic>;
          if (a['role'] == 'session' &&
              (a['sessionId'] as num).toInt() == s.id) {
            await c.closeWindow();
          }
        }
      } catch (_) {}
    }
    await windowManager.destroy();
  }

  Future<void> _boot() async {
    try {
      final b = HelmBridge.open();
      await b.initRegistry();
      final root = await AppPaths.root();
      setState(() {
        _bridge = b;
        _hello = b.hello();
        _thumbsRoot = root.path;
        _error = null;
        _reloadCards();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  void _reloadCards() {
    final b = _bridge;
    if (b == null) return;
    final openByKey = {
      for (final s in _sessions.items) sessionKey(s.host, s.port): s.id,
    };
    _cards = b.registryList().map((raw) {
      final m = Map<String, dynamic>.from(raw as Map);
      final id = m['id'] as String? ?? '';
      return LibraryCard.fromJson(m, openSessionId: openByKey[id]);
    }).toList();
    try {
      _profiles = b.profileList().map((raw) {
        return ConnectionProfileCard.fromJson(
          Map<String, dynamic>.from(raw as Map),
        );
      }).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    } catch (_) {
      _profiles = [];
    }
  }

  void _refreshLiveThumbs() {
    final b = _bridge;
    if (b == null || _sessions.isEmpty) return;
    var changed = false;
    for (final s in _sessions.items) {
      try {
        final (w, h) = b.fbSize(s.id);
        if (w <= 0 || h <= 0) continue;
        final rgba = b.fbCopy(s.id, w, h);
        final jpg = encodeFbJpegThumb(rgba, w, h);
        if (jpg == null) continue;
        _liveThumbs[s.key] = jpg;
        changed = true;
      } catch (_) {}
    }
    if (changed && mounted) setState(() {});
  }

  Future<void> _openSessionWindow(
    int id,
    String title, {
    required String host,
    required int port,
    String? username,
    String? profileId,
    bool preferVencrypt = false,
    bool acceptInvalidCerts = false,
  }) async {
    final args = jsonEncode({
      'role': 'session',
      'sessionId': id,
      'title': title,
      'entryId': title,
      'host': host,
      'port': port,
      if (username != null) 'username': username,
      if (profileId != null) 'profile_id': profileId,
      'prefer_vencrypt': preferVencrypt,
      'accept_invalid_certs': acceptInvalidCerts,
    });
    for (final c in await WindowController.getAll()) {
      if (c.arguments.isEmpty) continue;
      try {
        final a = jsonDecode(c.arguments) as Map<String, dynamic>;
        if (a['role'] == 'session' &&
            ((a['sessionId'] as num?)?.toInt() == id ||
                a['title'] == title)) {
          await c.show();
          return;
        }
      } catch (_) {}
    }
    final created = await WindowController.create(
      WindowConfiguration(arguments: args, hiddenAtLaunch: true),
    );
    await created.show();
  }

  Future<void> _persistEntryCredentials(
    Map<String, dynamic> entry, {
    String? password,
    required bool savePassword,
    bool clearPassword = false,
  }) async {
    final id = entry['id'] as String;
    try {
      await persistEntryCredentials(
        _credentials,
        id,
        password: password,
        savePassword: savePassword,
        clearPassword: clearPassword,
      );
    } on CredentialStoreException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  Map<String, dynamic> _mergeEntryPreserving(
    Map<String, dynamic> entry,
    String id,
  ) {
    for (final raw in _bridge!.registryList()) {
      final m = Map<String, dynamic>.from(raw as Map);
      if (m['id'] == id) {
        return {
          ...m,
          ...entry,
          if (entry['thumb_path'] == null && m['thumb_path'] != null)
            'thumb_path': m['thumb_path'],
          if (entry['tags'] == null || (entry['tags'] as List).isEmpty)
            'tags': m['tags'],
        };
      }
    }
    return entry;
  }

  Future<void> _connectCard(LibraryCard card) async {
    Map<String, dynamic>? resolved;
    try {
      resolved = _bridge?.registryResolve(card.id);
    } catch (_) {}
    final profileId =
        (resolved?['profile_id'] as String?) ?? card.profileId;
    final connectHost =
        (resolved?['connect_host'] as String?)?.trim().isNotEmpty == true
            ? resolved!['connect_host'] as String
            : card.host;
    final pwd = await resolvePassword(
      store: _credentials,
      entryId: card.id,
      profileId: profileId,
    );
    final port = connectPortForCard(card: card, resolved: resolved);
    await _connectTo(
      connectHost,
      port,
      entry: {
        ...card.toJson(),
        'host': card.host,
        'id': sessionKey(connectHost, port),
        if (card.displayNumber == null &&
            (resolved?['display_number'] as num?) != null)
          'display_number': (resolved!['display_number'] as num).toInt(),
      },
      username: (resolved?['username'] as String?) ?? card.username,
      password: pwd,
      preferVencrypt:
          (resolved?['prefer_vencrypt'] as bool?) ?? card.preferVencrypt,
      acceptInvalidCerts: (resolved?['accept_invalid_certs'] as bool?) ??
          card.acceptInvalidCerts,
      displayName: card.displayName,
      profileId: profileId,
    );
  }

  bool _isNativeSessionAlive(HelmBridge b, int sessionId) {
    try {
      b.fbSize(sessionId);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _connectTo(
    String host,
    int port, {
    Map<String, dynamic>? entry,
    String? displayName,
    String? username,
    String? password,
    bool preferVencrypt = false,
    bool acceptInvalidCerts = false,
    bool savePassword = false,
    String? profileId,
    bool savePasswordToProfile = false,
  }) async {
    final b = _bridge;
    if (b == null || _connecting) return;

    final existing = _sessions.findByHostPort(host, port);
    final shell = SessionShellRouter(preferred: widget.sessionShell)
        .routeForNew(existing: existing);
    if (existing != null) {
      if (_isNativeSessionAlive(b, existing.id)) {
        b.grab(existing.id);
        if (existing.shell == SessionShell.tabs || shell == SessionShell.tabs) {
          setState(() {
            _activeTabSessionId = existing.id;
            _libraryTabSelected = false;
            _sessions.applyTabGrabPolicy(activeId: existing.id);
          });
        } else {
          await _openSessionWindow(
            existing.id,
            sessionKey(host, port),
            host: host,
            port: port,
            username: username,
            profileId: profileId,
            preferVencrypt: preferVencrypt,
            acceptInvalidCerts: acceptInvalidCerts,
          );
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Session already open')),
          );
        }
        return;
      }
      _sessions.removeBySessionId(existing.id);
      try {
        b.close(existing.id);
      } catch (_) {}
      if (mounted) setState(_reloadCards);
    }

    setState(() => _connecting = true);
    try {
      await _connectWithAuth(
        b,
        host,
        port,
        entry: entry,
        username: username,
        password: password,
        displayName: displayName,
        preferVencrypt: preferVencrypt,
        acceptInvalidCerts: acceptInvalidCerts,
        savePassword: savePassword,
        shell: shell,
        profileId: profileId,
        savePasswordToProfile: savePasswordToProfile,
      );
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _connectWithAuth(
    HelmBridge b,
    String host,
    int port, {
    Map<String, dynamic>? entry,
    String? displayName,
    String? username,
    String? password,
    bool preferVencrypt = false,
    bool acceptInvalidCerts = false,
    bool savePassword = false,
    bool persistUsername = false,
    SessionShell shell = SessionShell.windows,
    String? profileId,
    bool savePasswordToProfile = false,
  }) async {
    try {
      final id = b.connect(
        host,
        port,
        username: username,
        password: password,
        preferVencrypt: preferVencrypt,
        acceptInvalidCerts: acceptInvalidCerts,
        bandwidthPreset: BandwidthPresetX.fromPrefs(
          entry?['bandwidth_preset'] as String?,
        ).wireCode,
        qualityLevel: (entry?['quality_level'] as num?)?.toInt(),
        compressLevel: (entry?['compress_level'] as num?)?.toInt(),
      );
      widget.logger.info('connected', {
        'host': host,
        'port': port,
        'sessionId': id,
        'vencrypt': preferVencrypt,
        'shell': shell.prefsKey,
      });
      b.grab(id);
      final key = sessionKey(host, port);
      var upsert = entry ??
          {
            'id': key,
            'host': host,
            'port': port,
            'display_number': displayFromPort(port),
            'prefer_vencrypt': preferVencrypt,
            'accept_invalid_certs': acceptInvalidCerts,
          };
      upsert = _mergeEntryPreserving(upsert, key);
      upsert['last_connected_at'] =
          DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (displayName != null && displayName.isNotEmpty) {
        upsert['display_name'] = displayName;
      }
      if (persistUsername && username != null && username.isNotEmpty) {
        upsert['username'] = username;
      }
      b.registryUpsertJson(upsert);
      if (savePassword &&
          password != null &&
          password.isNotEmpty &&
          profileId != null &&
          savePasswordToProfile) {
        // Auth "remember" under a group → shared profile vault.
        try {
          await persistProfileCredentials(
            _credentials,
            profileId,
            password: password,
            savePassword: true,
          );
        } on CredentialStoreException catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e.message)),
            );
          }
        }
      } else {
        await _persistEntryCredentials(
          upsert,
          password: password,
          savePassword: savePassword,
        );
      }
      setState(() {
        _sessions.add(OpenSessionRef(
          id: id,
          host: host,
          port: port,
          shell: shell,
          profileId: profileId,
          bandwidthPreset: BandwidthPresetX.fromPrefs(
            upsert['bandwidth_preset'] as String?,
          ),
          qualityLevel: (upsert['quality_level'] as num?)?.toInt(),
          compressLevel: (upsert['compress_level'] as num?)?.toInt(),
        ));
        if (shell == SessionShell.tabs) {
          _activeTabSessionId = id;
          _libraryTabSelected = false;
          _sessions.applyTabGrabPolicy(activeId: id);
        }
        _reloadCards();
      });
      if (shell == SessionShell.windows) {
        await _openSessionWindow(
          id,
          key,
          host: host,
          port: port,
          username: username,
          profileId: profileId,
          preferVencrypt: preferVencrypt,
          acceptInvalidCerts: acceptInvalidCerts,
        );
      }
    } on StateError catch (e) {
      final need = parseAuthNeed(e.message);
      if (need != AuthNeed.none && mounted) {
        final creds = await showAuthDialog(
          context,
          need: need,
          initialUsername: username,
          connectingTo: sessionKey(host, port),
        );
        if (creds == null) return;
        await _connectWithAuth(
          b,
          host,
          port,
          entry: entry,
          username: creds.username ?? username,
          password: creds.password ?? password,
          displayName: displayName,
          preferVencrypt: preferVencrypt,
          acceptInvalidCerts: acceptInvalidCerts,
          savePassword: savePassword || creds.savePermanently,
          persistUsername: need == AuthNeed.usernamePassword,
          shell: shell,
          profileId: profileId,
          savePasswordToProfile: savePasswordToProfile ||
              (creds.savePermanently && profileId != null),
        );
        return;
      }
      if (mounted) {
        widget.logger.error('connect failed', {
          'host': host,
          'port': port,
          'error': _connectErrorMessage(e),
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_connectErrorMessage(e))),
        );
      }
    } catch (e) {
      if (mounted) {
        widget.logger.error('connect failed', {
          'host': host,
          'port': port,
          'error': _connectErrorMessage(e),
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_connectErrorMessage(e))),
        );
      }
    }
  }

  String _connectErrorMessage(Object e) {
    final s = e is StateError ? e.message : e.toString();
    return s.startsWith('Bad state:')
        ? s.replaceFirst('Bad state: ', '')
        : 'Connect failed: $s';
  }

  Future<void> _handleEditorResult(ConnectionEditorResult result) async {
    final b = _bridge;
    if (b == null) return;
    final merged = _mergeEntryPreserving(result.entry, result.entry['id'] as String);
    b.registryUpsertJson(merged);
    await _persistEntryCredentials(
      merged,
      password: result.password,
      savePassword: result.savePassword,
      clearPassword: !result.savePassword,
    );
    setState(_reloadCards);
    if (result.connect) {
      final resolvedHost = () {
        try {
          final r = b.registryResolve(merged['id'] as String);
          return (r['connect_host'] as String?) ?? merged['host'] as String;
        } catch (_) {
          final pid = merged['profile_id'] as String?;
          if (pid != null) {
            for (final p in _profiles) {
              if (p.id == pid) {
                return qualifyHost(merged['host'] as String, p.domain);
              }
            }
          }
          return merged['host'] as String;
        }
      }();
      await _connectTo(
        resolvedHost,
        merged['port'] as int,
        entry: merged,
        displayName: merged['display_name'] as String?,
        username: merged['username'] as String?,
        password: result.password ??
            await resolvePassword(
              store: _credentials,
              entryId: merged['id'] as String,
              profileId: merged['profile_id'] as String?,
            ),
        preferVencrypt: merged['prefer_vencrypt'] as bool? ?? false,
        acceptInvalidCerts: merged['accept_invalid_certs'] as bool? ?? false,
        savePassword: result.savePassword,
        profileId: merged['profile_id'] as String?,
      );
    }
  }

  Future<void> _showNewEditor() async {
    final result = await showNewConnectionDialog(
      context,
      credentials: _credentials,
      profiles: _profileChoices(),
    );
    if (result != null) await _handleEditorResult(result);
  }

  Future<void> _editCard(LibraryCard card) async {
    final result = await showPropertiesDialog(
      context,
      existing: card,
      credentials: _credentials,
      profiles: _profileChoices(),
    );
    if (result != null) await _handleEditorResult(result);
  }

  List<ProfileChoice> _profileChoices() => [
        for (final p in _profiles)
          ProfileChoice.named(p.id, p.name, domain: p.domain),
      ];

  Future<void> _addressBarConnect() async {
    final raw = _search.text.trim();
    if (raw.isEmpty) {
      setState(() => _searchPatternError = 'Enter a host or VNC address');
      return;
    }

    final result = resolveQuickConnect(
      rawInput: raw,
      profiles: _profiles,
      filterProfileId: _profileFilterId,
    );
    if (result.error != null) {
      setState(() => _searchPatternError = result.error);
      return;
    }
    final target = result.target!;
    setState(() => _searchPatternError = null);

    final connectHost = target.connectHost;
    final port = target.port;
    final key = sessionKey(connectHost, port);
    var profileId = target.profileId;
    final short = target.entryHost;

    Map<String, dynamic>? entry;
    for (final c in _cards) {
      if (c.id == key ||
          (c.host == short && c.port == port) ||
          (c.host == connectHost && c.port == port)) {
        entry = c.toJson();
        profileId ??= c.profileId;
        break;
      }
    }
    entry ??= {
      'id': key,
      'host': short,
      'port': port,
      if (target.displayNumber != null) 'display_number': target.displayNumber,
      if (profileId != null) 'profile_id': profileId,
    };

    final pwd = await resolvePassword(
      store: _credentials,
      entryId: entry['id'] as String? ?? key,
      profileId: profileId,
    );
    await _connectTo(
      connectHost,
      port,
      entry: entry,
      username: entry['username'] as String?,
      password: pwd,
      preferVencrypt: entry['prefer_vencrypt'] as bool? ?? false,
      acceptInvalidCerts: entry['accept_invalid_certs'] as bool? ?? false,
      displayName: entry['display_name'] as String?,
      profileId: profileId,
    );
  }

  Future<void> _cardAction(String action, LibraryCard card) async {
    switch (action) {
      case 'open':
        await _connectCard(card);
      case 'edit':
        await _editCard(card);
      case 'export':
        await _exportEntry(card);
      case 'delete':
        _bridge?.registryRemove(card.id);
        try {
          await _credentials.deletePassword(card.id);
        } on CredentialStoreException catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e.message)),
            );
          }
        }
        setState(_reloadCards);
      case 'disconnect':
        final open = _sessions.findBySessionId(card.openSessionId ?? -1) ??
            _sessions.findByHostPort(card.host, card.port);
        if (open != null) await _disconnect(open);
    }
  }

  Future<void> _disconnect(OpenSessionRef s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect session?'),
        content: Text(
          'Disconnect from ${s.host}:${s.port}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final key = sessionKey(s.host, s.port);
    try {
      await saveSessionThumb(_bridge!, key, s.id);
    } catch (_) {}
    try {
      _bridge?.close(s.id);
    } catch (_) {}
    if (s.shell == SessionShell.windows) {
      for (final c in await WindowController.getAll()) {
        if (c.arguments.isEmpty) continue;
        try {
          final a = jsonDecode(c.arguments) as Map<String, dynamic>;
          if (a['role'] == 'session' &&
              (a['sessionId'] as num).toInt() == s.id) {
            await c.closeWindow();
          }
        } catch (_) {}
      }
    }
    setState(() {
      _sessions.removeBySessionId(s.id);
      if (_activeTabSessionId == s.id) {
        _activeTabSessionId = _sessions.tabSessions.isEmpty
            ? null
            : _sessions.tabSessions.last.id;
        _libraryTabSelected = _activeTabSessionId == null;
      }
      _liveThumbs.remove(key);
      _reloadCards();
    });
  }

  Future<void> _editProfile([ConnectionProfileCard? existing]) async {
    final result = await showProfileEditor(
      context,
      existing: existing,
      credentials: _credentials,
    );
    if (result == null) return;
    final json = result.profile.toJson();
    widget.logger.info('profile upsert', {
      'id': result.profile.id,
      'default_display': result.profile.defaultDisplay,
      'json': json,
    });
    try {
      _bridge?.profileUpsertJson(json);
    } catch (e) {
      widget.logger.error('profile upsert failed', {'error': '$e', 'json': json});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save profile: $e')),
        );
      }
      return;
    }
    try {
      await persistProfileCredentials(
        _credentials,
        result.profile.id,
        password: result.password,
        savePassword: result.savePassword,
        clearPassword: result.clearPassword,
      );
    } on CredentialStoreException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
    // Confirm what actually landed after reload from FFI.
    setState(_reloadCards);
    ConnectionProfileCard? saved;
    for (final p in _profiles) {
      if (p.id == result.profile.id) {
        saved = p;
        break;
      }
    }
    widget.logger.info('profile after reload', {
      'id': result.profile.id,
      'default_display_sent': result.profile.defaultDisplay,
      'default_display_reloaded': saved?.defaultDisplay,
    });
    if (mounted) {
      final d = saved?.defaultDisplay;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            d == null
                ? 'Saved “${result.profile.name}” (default display: none)'
                : 'Saved “${result.profile.name}” (default display: :$d)',
          ),
        ),
      );
    }
  }

  Future<void> _deleteProfile(ConnectionProfileCard p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete profile?'),
        content: Text('Delete “${p.name}”? Hosts keep their own settings.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    _bridge?.profileRemove(p.id);
    if (_profileFilterId == p.id) _profileFilterId = null;
    setState(_reloadCards);
  }

  Future<void> _toggleSessionShell() async {
    final next = widget.sessionShell == SessionShell.windows
        ? SessionShell.tabs
        : SessionShell.windows;
    if (_sessions.isEmpty) {
      widget.onSessionShellChanged(next);
      return;
    }
    final migrate = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          next == SessionShell.tabs
              ? 'Switch to tabbed sessions?'
              : 'Switch to windowed sessions?',
        ),
        content: const Text(
          'Move open sessions into the new shell now? '
          '(May reconnect if the session cannot be reparented.)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('New connects only'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Move all'),
          ),
        ],
      ),
    );
    widget.onSessionShellChanged(next);
    if (migrate == true) {
      SessionShellRouter.migrateAll(_sessions, next);
      setState(() {
        if (next == SessionShell.tabs) {
          _libraryTabSelected = false;
          _activeTabSessionId = _sessions.tabSessions.isEmpty
              ? null
              : _sessions.tabSessions.first.id;
        } else {
          _libraryTabSelected = true;
          _activeTabSessionId = null;
        }
      });
      // Detach path: open windows for sessions now in windows shell.
      if (next == SessionShell.windows) {
        for (final s in _sessions.windowSessions) {
          await _openSessionWindow(
            s.id,
            s.key,
            host: s.host,
            port: s.port,
            profileId: s.profileId,
          );
        }
      }
    }
  }

  Future<void> _detachTab(int sessionId) async {
    final s = _sessions.findBySessionId(sessionId);
    if (s == null) return;
    _sessions.detachToWindow(sessionId);
    setState(() {
      if (_activeTabSessionId == sessionId) {
        _activeTabSessionId = _sessions.tabSessions.isEmpty
            ? null
            : _sessions.tabSessions.last.id;
        _libraryTabSelected = _activeTabSessionId == null;
      }
    });
    await _openSessionWindow(
      s.id,
      s.key,
      host: s.host,
      port: s.port,
      profileId: s.profileId,
    );
  }

  Future<void> _exportLibrary() async {
    final b = _bridge;
    if (b == null) return;
    final json = b.registryExport();
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export library',
      fileName: 'helmhost-library.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (path == null) return;
    await File(path).writeAsString(json);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Library exported')),
      );
    }
  }

  Future<void> _exportEntry(LibraryCard card) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export connection',
      fileName: safeExportFilename(card.id),
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (path == null) return;
    await File(path).writeAsString(exportEntryJson(card));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported ${card.title}')),
      );
    }
  }

  Future<void> _importLibrary() async {
    final b = _bridge;
    if (b == null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    final json = await File(path).readAsString();
    b.registryMergeJson(json);
    setState(_reloadCards);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Library imported')),
      );
    }
  }

  void _cycleTheme() {
    final next = switch (widget.themeMode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    widget.onThemeModeChanged(next);
  }

  void _toggleViewMode() {
    final next = widget.viewMode == LibraryViewMode.grid
        ? LibraryViewMode.list
        : LibraryViewMode.grid;
    widget.onViewModeChanged(next);
  }

  Widget _buildBody(List<LibraryCard> filtered) {
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/brand/helmhost-icon-256.png',
              width: 96,
              height: 96,
            ),
            const SizedBox(height: 16),
            Text(
              _cards.isEmpty
                  ? 'No connections yet.\nType a host above and press Connect, or click +'
                  : 'No matches',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    if (widget.viewMode == LibraryViewMode.list) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: filtered.length,
        itemBuilder: (context, i) {
          final card = filtered[i];
          return LibraryListTile(
            card: card,
            liveBytes: _liveThumbs[card.id] ??
                _liveThumbs[sessionKey(card.host, card.port)],
            thumbsRoot: _thumbsRoot,
            onTap: () => _connectCard(card),
            onAction: _cardAction,
          );
        },
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 340,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.05,
      ),
      itemCount: filtered.length,
      itemBuilder: (context, i) {
        final card = filtered[i];
        return LibraryGridCard(
          card: card,
          liveBytes: _liveThumbs[card.id] ??
              _liveThumbs[sessionKey(card.host, card.port)],
          thumbsRoot: _thumbsRoot,
          onTap: () => _connectCard(card),
          onAction: _cardAction,
        );
      },
    );
  }

  List<LibraryCard> _filteredCards() {
    var list = filterLibraryCardsRegex(_cards, _search.text);
    final pid = _profileFilterId;
    if (pid != null) {
      ConnectionProfileCard? profile;
      for (final p in _profiles) {
        if (p.id == pid) {
          profile = p;
          break;
        }
      }
      if (profile != null) {
        list = list.where((c) => cardMatchesProfile(c, profile!)).toList();
      }
    }
    return list;
  }

  Widget _buildLibraryPane() {
    final filtered = _filteredCards();
    return Row(
      children: [
        SizedBox(
          width: 180,
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                ListTile(
                  dense: true,
                  selected: _profileFilterId == null,
                  title: const Text('All'),
                  onTap: () => setState(() => _profileFilterId = null),
                ),
                for (final p in _profiles)
                  ListTile(
                    dense: true,
                    selected: _profileFilterId == p.id,
                    title: Text(p.name, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      normalizeDomain(p.domain).isEmpty
                          ? 'No domain — edit to set'
                          : p.domainLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: normalizeDomain(p.domain).isEmpty
                          ? TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12,
                            )
                          : null,
                    ),
                    onTap: () => setState(() => _profileFilterId = p.id),
                    onLongPress: () => _editProfile(p),
                    trailing: PopupMenuButton<String>(
                      onSelected: (a) async {
                        if (a == 'edit') await _editProfile(p);
                        if (a == 'delete') await _deleteProfile(p);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit…')),
                        PopupMenuItem(value: 'delete', child: Text('Delete…')),
                      ],
                    ),
                  ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.add, size: 18),
                  title: const Text('New profile…'),
                  onTap: () => _editProfile(),
                ),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _buildBody(filtered)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final useTabs = widget.sessionShell == SessionShell.tabs;
    final libraryPane = Column(
      children: [
        if (_error != null)
          ColoredBox(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              dense: true,
              title: Text(_error!, maxLines: 2),
              trailing:
                  TextButton(onPressed: _boot, child: const Text('Retry')),
            ),
          ),
        Expanded(child: _buildLibraryPane()),
      ],
    );

    final showLibraryChrome = !useTabs ||
        _libraryTabSelected ||
        _sessions.tabSessions.isEmpty;
    final statusText =
        _error != null ? 'Bridge error' : 'Helmhost - v · $_hello';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: Row(
          children: [
            const Text('HelmHost'),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: _search,
                enabled: !_connecting,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'VNC address or search…',
                  errorText: _searchPatternError,
                  prefixIcon: const Icon(Icons.lan_outlined, size: 20),
                  border: const OutlineInputBorder(),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onSubmitted: (_) => _addressBarConnect(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _connecting ? null : _addressBarConnect,
              child: const Text('Connect'),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'New connection',
              onPressed: _connecting ? null : _showNewEditor,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
      bottomNavigationBar: showLibraryChrome
          ? LibraryStatusBar(
              sessionShell: widget.sessionShell,
              viewMode: widget.viewMode,
              themeMode: widget.themeMode,
              statusText: statusText,
              onToggleShell: _toggleSessionShell,
              onToggleView: _toggleViewMode,
              onCycleTheme: _cycleTheme,
              onImport: _importLibrary,
              onExport: _exportLibrary,
            )
          : null,
      body: useTabs
          ? TabSessionWorkspace(
              sessions: _sessions.tabSessions,
              activeSessionId: _activeTabSessionId,
              librarySelected: _libraryTabSelected,
              libraryChild: libraryPane,
              prefs: widget.prefs,
              onLibrarySelected: () => setState(() {
                _libraryTabSelected = true;
                _sessions.applyTabGrabPolicy(activeId: null, wantGrab: false);
              }),
              onSelect: (id) => setState(() {
                _libraryTabSelected = false;
                _activeTabSessionId = id;
                _sessions.applyTabGrabPolicy(activeId: id);
                try {
                  _bridge?.grab(id);
                } catch (_) {}
              }),
              onClose: (id) {
                final s = _sessions.findBySessionId(id);
                if (s != null) unawaited(_disconnect(s));
              },
              onDetach: (id) => unawaited(_detachTab(id)),
            )
          : libraryPane,
    );
  }
}
