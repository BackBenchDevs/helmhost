import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import '../bridge.dart';
import '../logging/logger.dart';
import '../session_helpers.dart';
import '../storage/credential_store.dart';
import '../thumbs.dart';
import 'auth_dialog.dart';
import 'connection_editor.dart';
import 'library_card_widgets.dart';

extension WindowControllerExt on WindowController {
  Future<void> closeWindow() => invokeMethod('window_close');
}

class HubPage extends StatefulWidget {
  const HubPage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.viewMode,
    required this.onViewModeChanged,
    this.logger = const DebugPrintLogger(module: 'hub'),
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final LibraryViewMode viewMode;
  final ValueChanged<LibraryViewMode> onViewModeChanged;
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
  final _search = TextEditingController();
  final _sessions = <OpenSessionRef>[];
  bool _connecting = false;
  String? _thumbsRoot;
  final _liveThumbs = <String, Uint8List>{};
  Timer? _liveTimer;
  String? _searchPatternError;

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
    _boot();
  }

  void _onSearchChanged() {
    final q = _search.text.trim();
    if (q.isEmpty) {
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
    for (final s in List<OpenSessionRef>.from(_sessions)) {
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
      final support = await getApplicationSupportDirectory();
      setState(() {
        _bridge = b;
        _hello = b.hello();
        _thumbsRoot = support.path;
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
      for (final s in _sessions) sessionKey(s.host, s.port): s.id,
    };
    _cards = b.registryList().map((raw) {
      final m = Map<String, dynamic>.from(raw as Map);
      final id = m['id'] as String? ?? '';
      return LibraryCard.fromJson(m, openSessionId: openByKey[id]);
    }).toList();
  }

  void _refreshLiveThumbs() {
    final b = _bridge;
    if (b == null || _sessions.isEmpty) return;
    var changed = false;
    for (final s in _sessions) {
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

  Future<void> _openSessionWindow(int id, String title) async {
    final args = jsonEncode({
      'role': 'session',
      'sessionId': id,
      'title': title,
      'entryId': title,
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
  }) async {
    final id = entry['id'] as String;
    try {
      if (savePassword && password != null && password.isNotEmpty) {
        await _credentials.writePassword(id, password);
      } else if (!savePassword) {
        await _credentials.deletePassword(id);
      }
    } on CredentialStoreException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  Future<String?> _readPasswordSafe(String entryId) async {
    try {
      return await _credentials.readPassword(entryId);
    } on CredentialStoreException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
      return null;
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
    final pwd = await _readPasswordSafe(card.id);
    await _connectTo(
      card.host,
      card.port,
      entry: card.toJson(),
      username: card.username,
      password: pwd,
      preferVencrypt: card.preferVencrypt,
      acceptInvalidCerts: card.acceptInvalidCerts,
      displayName: card.displayName,
    );
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
  }) async {
    final b = _bridge;
    if (b == null || _connecting) return;

    final existing = findOpenByHostPort(_sessions, host, port);
    if (existing != null) {
      b.grab(existing.id);
      await _openSessionWindow(existing.id, sessionKey(host, port));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session already open')),
        );
      }
      return;
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
  }) async {
    try {
      final id = b.connect(
        host,
        port,
        username: username,
        password: password,
        preferVencrypt: preferVencrypt,
        acceptInvalidCerts: acceptInvalidCerts,
      );
      widget.logger.info('connected', {
        'host': host,
        'port': port,
        'sessionId': id,
        'vencrypt': preferVencrypt,
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
      await _persistEntryCredentials(
        upsert,
        password: password,
        savePassword: savePassword,
      );
      setState(() {
        _sessions.add(OpenSessionRef(id: id, host: host, port: port));
        _reloadCards();
      });
      await _openSessionWindow(id, key);
    } on StateError catch (e) {
      final need = parseAuthNeed(e.message);
      if (need != AuthNeed.none && mounted) {
        final creds = await showAuthDialog(
          context,
          need: need,
          initialUsername: username,
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
          savePassword: savePassword || creds.password != null,
          persistUsername: need == AuthNeed.usernamePassword,
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
    );
    setState(_reloadCards);
    if (result.connect) {
      await _connectTo(
        merged['host'] as String,
        merged['port'] as int,
        entry: merged,
        displayName: merged['display_name'] as String?,
        username: merged['username'] as String?,
        password: result.password ??
            await _readPasswordSafe(merged['id'] as String),
        preferVencrypt: merged['prefer_vencrypt'] as bool? ?? false,
        acceptInvalidCerts: merged['accept_invalid_certs'] as bool? ?? false,
        savePassword: result.savePassword,
      );
    }
  }

  Future<void> _showNewEditor() async {
    final result = await showConnectionEditor(
      context,
      credentials: _credentials,
    );
    if (result != null) await _handleEditorResult(result);
  }

  Future<void> _editCard(LibraryCard card) async {
    final result = await showConnectionEditor(
      context,
      existing: card,
      credentials: _credentials,
    );
    if (result != null) await _handleEditorResult(result);
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
        OpenSessionRef? open;
        for (final s in _sessions) {
          if (s.id == card.openSessionId) {
            open = s;
            break;
          }
        }
        if (open != null) await _disconnect(open);
    }
  }

  Future<void> _disconnect(OpenSessionRef s) async {
    final key = sessionKey(s.host, s.port);
    try {
      await saveSessionThumb(_bridge!, key, s.id);
    } catch (_) {}
    try {
      _bridge?.close(s.id);
    } catch (_) {}
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
    setState(() {
      _sessions.removeWhere((x) => x.id == s.id);
      _liveThumbs.remove(key);
      _reloadCards();
    });
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
                  ? 'No saved connections yet.\nTap + to connect.'
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

  @override
  Widget build(BuildContext context) {
    final filtered = filterLibraryCardsRegex(_cards, _search.text);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            tooltip: widget.viewMode == LibraryViewMode.grid
                ? 'List view'
                : 'Grid view',
            onPressed: _toggleViewMode,
            icon: Icon(
              widget.viewMode == LibraryViewMode.grid
                  ? Icons.view_list
                  : Icons.grid_view,
            ),
          ),
          IconButton(
            tooltip: 'Theme',
            onPressed: _cycleTheme,
            icon: Icon(switch (widget.themeMode) {
              ThemeMode.light => Icons.light_mode,
              ThemeMode.dark => Icons.dark_mode,
              ThemeMode.system => Icons.brightness_auto,
            }),
          ),
          IconButton(
            tooltip: 'Import',
            onPressed: _importLibrary,
            icon: const Icon(Icons.file_download_outlined),
          ),
          IconButton(
            tooltip: 'Export library',
            onPressed: _exportLibrary,
            icon: const Icon(Icons.file_upload_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _connecting ? null : _showNewEditor,
        child: const Icon(Icons.add),
      ),
      body: Column(
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Regex search (host, name, tags…)',
                errorText: _searchPatternError,
                isDense: true,
              ),
            ),
          ),
          Expanded(child: _buildBody(filtered)),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              _error != null ? 'Bridge error' : 'Helmhost · $_hello',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
