import 'package:flutter/material.dart';

import '../session_helpers.dart';
import '../storage/credential_store.dart';
import 'vnc_address.dart';

/// Result from New Connection or Properties dialogs.
class ConnectionEditorResult {
  const ConnectionEditorResult({
    required this.entry,
    this.password,
    required this.savePassword,
    required this.connect,
  });

  final Map<String, dynamic> entry;
  final String? password;
  final bool savePassword;
  final bool connect;
}

/// Profile option for Properties dropdown.
class ProfileChoice {
  const ProfileChoice.auto()
      : id = null,
        none = false,
        label = 'Auto',
        domain = '';
  const ProfileChoice.none()
      : id = null,
        none = true,
        label = 'None',
        domain = '';
  const ProfileChoice.named(this.id, this.label, {this.domain = ''})
      : none = false;

  final String? id;
  final bool none;
  final String label;
  final String domain;
}

/// Minimal RealVNC-style New Connection dialog.
Future<ConnectionEditorResult?> showNewConnectionDialog(
  BuildContext context, {
  required ICredentialStore credentials,
  List<ProfileChoice> profiles = const [],
}) {
  return showDialog<ConnectionEditorResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _NewConnectionDialog(
      credentials: credentials,
      profiles: profiles,
    ),
  );
}

/// Full Properties dialog (edit existing or Options from New Connection).
Future<ConnectionEditorResult?> showPropertiesDialog(
  BuildContext context, {
  LibraryCard? existing,
  Map<String, dynamic>? draft,
  required ICredentialStore credentials,
  List<ProfileChoice> profiles = const [],
  bool connectOnSave = false,
}) {
  return showDialog<ConnectionEditorResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _PropertiesDialog(
      existing: existing,
      draft: draft,
      credentials: credentials,
      profiles: profiles,
      connectOnSave: connectOnSave,
    ),
  );
}

/// Backward-compatible entry: new → New Connection; edit → Properties.
Future<ConnectionEditorResult?> showConnectionEditor(
  BuildContext context, {
  LibraryCard? existing,
  required ICredentialStore credentials,
  bool connectOnSave = false,
  List<ProfileChoice> profiles = const [],
}) {
  if (existing != null) {
    return showPropertiesDialog(
      context,
      existing: existing,
      credentials: credentials,
      profiles: profiles,
      connectOnSave: connectOnSave,
    );
  }
  return showNewConnectionDialog(
    context,
    credentials: credentials,
    profiles: profiles,
  );
}

class _NewConnectionDialog extends StatefulWidget {
  const _NewConnectionDialog({
    required this.credentials,
    this.profiles = const [],
  });

  final ICredentialStore credentials;
  final List<ProfileChoice> profiles;

  @override
  State<_NewConnectionDialog> createState() => _NewConnectionDialogState();
}

class _NewConnectionDialogState extends State<_NewConnectionDialog> {
  final _server = TextEditingController();
  final _name = TextEditingController();
  var _preferVencrypt = true;
  var _acceptInvalidCerts = false;
  String? _error;

  // Carried from Options (Properties) if user opened it.
  Map<String, dynamic>? _extra;
  String? _password;
  var _savePassword = false;

  @override
  void dispose() {
    _server.dispose();
    _name.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _buildEntry() {
    final parsed = tryParseVncAddress(_server.text);
    if (parsed == null) {
      setState(() => _error = 'Enter host, host:display, or host::port');
      return null;
    }
    setState(() => _error = null);
    final base = <String, dynamic>{
      'id': parsed.sessionId,
      'host': parsed.host,
      'port': parsed.port,
      if (parsed.displayNumber != null) 'display_number': parsed.displayNumber,
      'display_name':
          _name.text.trim().isEmpty ? null : _name.text.trim(),
      'prefer_vencrypt': _preferVencrypt,
      'accept_invalid_certs': _acceptInvalidCerts,
      'view_only': false,
      'tags': <String>[],
    };
    if (_extra != null) {
      return {
        ..._extra!,
        ...base,
        'id': parsed.sessionId,
        'host': parsed.host,
        'port': parsed.port,
      };
    }
    return base;
  }

  void _pop({required bool connect}) {
    final entry = _buildEntry();
    if (entry == null) return;
    Navigator.pop(
      context,
      ConnectionEditorResult(
        entry: entry,
        password: _password,
        savePassword: _savePassword,
        connect: connect,
      ),
    );
  }

  Future<void> _openOptions() async {
    final draft = _buildEntry();
    if (draft == null) return;
    final result = await showPropertiesDialog(
      context,
      draft: draft,
      credentials: widget.credentials,
      profiles: widget.profiles,
    );
    if (result == null || !mounted) return;
    setState(() {
      _extra = result.entry;
      _password = result.password;
      _savePassword = result.savePassword;
      _preferVencrypt = result.entry['prefer_vencrypt'] as bool? ?? _preferVencrypt;
      _acceptInvalidCerts =
          result.entry['accept_invalid_certs'] as bool? ?? _acceptInvalidCerts;
      final dn = result.entry['display_name'] as String?;
      if (dn != null) _name.text = dn;
      final host = result.entry['host'] as String? ?? '';
      final port = (result.entry['port'] as num?)?.toInt() ?? 5900;
      final disp = (result.entry['display_number'] as num?)?.toInt();
      if (disp != null) {
        _server.text = '$host:$disp';
      } else if (port == 5900) {
        _server.text = host;
      } else {
        _server.text = '$host::$port';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Connection'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _server,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'VNC Server',
                  hintText: 'host, host:1, or host::5900',
                  errorText: _error,
                ),
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _pop(connect: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'Optional display name',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<bool>(
                value: _preferVencrypt,
                decoration: const InputDecoration(labelText: 'Encryption'),
                items: const [
                  DropdownMenuItem(
                    value: true,
                    child: Text('Prefer VeNCrypt / TLS'),
                  ),
                  DropdownMenuItem(
                    value: false,
                    child: Text('Standard (server chooses)'),
                  ),
                ],
                onChanged: (v) =>
                    setState(() => _preferVencrypt = v ?? true),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Accept invalid certificates'),
                value: _acceptInvalidCerts,
                onChanged: (v) =>
                    setState(() => _acceptInvalidCerts = v ?? false),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _openOptions, child: const Text('Options…')),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => _pop(connect: true),
          child: const Text('Connect'),
        ),
        FilledButton.tonal(
          onPressed: () => _pop(connect: false),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

class _PropertiesDialog extends StatefulWidget {
  const _PropertiesDialog({
    this.existing,
    this.draft,
    required this.credentials,
    this.profiles = const [],
    this.connectOnSave = false,
  });

  final LibraryCard? existing;
  final Map<String, dynamic>? draft;
  final ICredentialStore credentials;
  final List<ProfileChoice> profiles;
  final bool connectOnSave;

  @override
  State<_PropertiesDialog> createState() => _PropertiesDialogState();
}

class _PropertiesDialogState extends State<_PropertiesDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final TextEditingController _host;
  late final TextEditingController _display;
  late final TextEditingController _port;
  late final TextEditingController _name;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _tags;
  late final TextEditingController _notes;
  var _syncing = false;
  var _obscurePassword = true;
  var _savePassword = false;
  var _preferVencrypt = false;
  var _acceptInvalidCerts = false;
  var _viewOnly = false;
  var _loaded = false;
  /// null = auto, '__none__' = none, else profile id
  String? _profileKey;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    final e = widget.existing;
    final d = widget.draft;
    _host = TextEditingController(
      text: e?.host ?? d?['host'] as String? ?? '127.0.0.1',
    );
    final port = e?.port ?? (d?['port'] as num?)?.toInt() ?? 5900;
    final disp = e?.displayNumber ??
        (d?['display_number'] as num?)?.toInt() ??
        displayFromPort(port) ??
        0;
    _display = TextEditingController(text: '$disp');
    _port = TextEditingController(text: '$port');
    _name = TextEditingController(
      text: e?.displayName ?? d?['display_name'] as String? ?? '',
    );
    _username = TextEditingController(
      text: e?.username ?? d?['username'] as String? ?? '',
    );
    _password = TextEditingController();
    final tags = e?.tags ??
        ((d?['tags'] as List?)?.map((t) => t.toString()).toList() ?? []);
    _tags = TextEditingController(text: tags.join(', '));
    _notes = TextEditingController(
      text: e?.notes ?? d?['notes'] as String? ?? '',
    );
    _preferVencrypt =
        e?.preferVencrypt ?? d?['prefer_vencrypt'] as bool? ?? false;
    _acceptInvalidCerts =
        e?.acceptInvalidCerts ?? d?['accept_invalid_certs'] as bool? ?? false;
    _viewOnly = e?.viewOnly ?? d?['view_only'] as bool? ?? false;
    _savePassword = e != null;
    if (e?.profileNone == true || d?['profile_none'] == true) {
      _profileKey = '__none__';
    } else if ((e?.profileId ?? d?['profile_id'] as String?) != null) {
      _profileKey = e?.profileId ?? d?['profile_id'] as String?;
    } else {
      _profileKey = null; // auto
    }
    _loadPassword();
  }

  Future<void> _loadPassword() async {
    final id = widget.existing?.id ?? widget.draft?['id'] as String?;
    if (id == null) {
      setState(() => _loaded = true);
      return;
    }
    try {
      final pwd = await widget.credentials.readPassword(id);
      if (pwd != null && mounted) _password.text = pwd;
    } on CredentialStoreException {
      // leave empty
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _host.dispose();
    _display.dispose();
    _port.dispose();
    _name.dispose();
    _username.dispose();
    _password.dispose();
    _tags.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _syncDisplayFromPort(int port) {
    final d = displayFromPort(port);
    if (d != null) {
      _syncing = true;
      _display.text = '$d';
      _syncing = false;
    }
  }

  void _syncPortFromDisplay(int display) {
    _syncing = true;
    _port.text = '${portFromDisplay(display)}';
    _syncing = false;
  }

  Map<String, dynamic> _buildEntry() {
    final profileNone = _profileKey == '__none__';
    final profileId =
        (!profileNone && _profileKey != null && _profileKey!.isNotEmpty)
            ? _profileKey
            : null;
    String? domain;
    if (profileId != null) {
      for (final p in widget.profiles) {
        if (p.id == profileId) {
          domain = p.domain;
          break;
        }
      }
    }
    var host = _host.text.trim();
    if (domain != null && domain.isNotEmpty) {
      host = shortHost(host, domain);
      if (host.isEmpty) host = _host.text.trim();
    }
    final port = int.tryParse(_port.text.trim()) ?? 5900;
    final connectHost =
        (domain != null && domain.isNotEmpty) ? qualifyHost(host, domain) : host;
    final id = sessionKey(connectHost, port);
    return {
      'id': id,
      'host': host,
      'port': port,
      'display_number': displayFromPort(port) ??
          int.tryParse(_display.text.trim()),
      'display_name':
          _name.text.trim().isEmpty ? null : _name.text.trim(),
      'username':
          _username.text.trim().isEmpty ? null : _username.text.trim(),
      'prefer_vencrypt': _preferVencrypt,
      'accept_invalid_certs': _acceptInvalidCerts,
      'view_only': _viewOnly,
      'tags': _tags.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList(),
      if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
      if (profileId != null) 'profile_id': profileId,
      'profile_none': profileNone,
      if (widget.existing?.thumbPath != null)
        'thumb_path': widget.existing!.thumbPath,
      if (widget.existing?.lastConnectedAt != null)
        'last_connected_at': widget.existing!.lastConnectedAt,
      if (widget.draft?['thumb_path'] != null)
        'thumb_path': widget.draft!['thumb_path'],
      if (widget.draft?['last_connected_at'] != null)
        'last_connected_at': widget.draft!['last_connected_at'],
    };
  }

  String? get _selectedProfileDomain {
    if (_profileKey == null || _profileKey == '__none__') return null;
    for (final p in widget.profiles) {
      if (p.id == _profileKey) return p.domain;
    }
    return null;
  }

  void _submit({required bool connect}) {
    if (_host.text.trim().isEmpty) return;
    Navigator.pop(
      context,
      ConnectionEditorResult(
        entry: _buildEntry(),
        password: _password.text.isEmpty ? null : _password.text,
        savePassword: _savePassword,
        connect: connect,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const AlertDialog(
        content: SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final title = widget.existing != null
        ? 'Properties — ${widget.existing!.title}'
        : 'Properties';
    final profileItems = <DropdownMenuItem<String?>>[
      const DropdownMenuItem(value: null, child: Text('Auto')),
      const DropdownMenuItem(value: '__none__', child: Text('None')),
      ...widget.profiles
          .where((p) => p.id != null)
          .map(
            (p) => DropdownMenuItem(value: p.id, child: Text(p.label)),
          ),
    ];

    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          children: [
            TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: 'General'),
                Tab(text: 'Security'),
                Tab(text: 'Notes'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  ListView(
                    padding: const EdgeInsets.only(top: 12),
                    children: [
                      TextField(
                        controller: _name,
                        decoration:
                            const InputDecoration(labelText: 'Name'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _host,
                        decoration: InputDecoration(
                          labelText: _selectedProfileDomain != null &&
                                  _selectedProfileDomain!.isNotEmpty
                              ? 'Hostname (short)'
                              : 'VNC Server / Hostname',
                          helperText: () {
                            final d = _selectedProfileDomain;
                            if (d == null || d.isEmpty) return null;
                            final h = _host.text.trim();
                            if (h.isEmpty) {
                              return 'Will connect as host.$d';
                            }
                            return 'Will connect to ${qualifyHost(h, d)}';
                          }(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _display,
                              decoration: const InputDecoration(
                                labelText: 'Display (:N)',
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (v) {
                                if (_syncing) return;
                                final n = int.tryParse(v.trim());
                                if (n == null) return;
                                setState(() => _syncPortFromDisplay(n));
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _port,
                              decoration: const InputDecoration(
                                labelText: 'TCP port',
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (v) {
                                if (_syncing) return;
                                final p = int.tryParse(v.trim());
                                if (p == null) return;
                                setState(() => _syncDisplayFromPort(p));
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        value: _profileKey,
                        decoration:
                            const InputDecoration(labelText: 'Profile'),
                        items: profileItems,
                        onChanged: (v) => setState(() {
                          _profileKey = v;
                          final d = _selectedProfileDomain;
                          if (d != null && d.isNotEmpty) {
                            _host.text = shortHost(_host.text, d);
                          }
                        }),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _tags,
                        decoration: const InputDecoration(
                          labelText: 'Tags (comma-separated)',
                        ),
                      ),
                    ],
                  ),
                  ListView(
                    padding: const EdgeInsets.only(top: 12),
                    children: [
                      TextField(
                        controller: _username,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _password,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('Save password on this device'),
                        value: _savePassword,
                        onChanged: (v) =>
                            setState(() => _savePassword = v ?? false),
                      ),
                      DropdownButtonFormField<bool>(
                        value: _preferVencrypt,
                        decoration:
                            const InputDecoration(labelText: 'Encryption'),
                        items: const [
                          DropdownMenuItem(
                            value: true,
                            child: Text('Prefer VeNCrypt / TLS'),
                          ),
                          DropdownMenuItem(
                            value: false,
                            child: Text('Standard (server chooses)'),
                          ),
                        ],
                        onChanged: (v) => setState(
                          () => _preferVencrypt = v ?? false,
                        ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('Accept invalid certificates'),
                        value: _acceptInvalidCerts,
                        onChanged: (v) => setState(
                          () => _acceptInvalidCerts = v ?? false,
                        ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('View only'),
                        value: _viewOnly,
                        onChanged: (v) =>
                            setState(() => _viewOnly = v ?? false),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextField(
                      controller: _notes,
                      decoration:
                          const InputDecoration(labelText: 'Notes'),
                      maxLines: 8,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (widget.connectOnSave)
          FilledButton(
            onPressed: () => _submit(connect: true),
            child: const Text('Connect'),
          ),
        FilledButton(
          onPressed: () => _submit(connect: false),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
