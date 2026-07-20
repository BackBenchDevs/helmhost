import 'package:flutter/material.dart';

import '../session_helpers.dart';
import '../storage/credential_store.dart';

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

Future<ConnectionEditorResult?> showConnectionEditor(
  BuildContext context, {
  LibraryCard? existing,
  required ICredentialStore credentials,
  bool connectOnSave = false,
}) {
  return showModalBottomSheet<ConnectionEditorResult>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _ConnectionEditorSheet(
      existing: existing,
      credentials: credentials,
      connectOnSave: connectOnSave,
    ),
  );
}

class _ConnectionEditorSheet extends StatefulWidget {
  const _ConnectionEditorSheet({
    this.existing,
    required this.credentials,
    required this.connectOnSave,
  });

  final LibraryCard? existing;
  final ICredentialStore credentials;
  final bool connectOnSave;

  @override
  State<_ConnectionEditorSheet> createState() => _ConnectionEditorSheetState();
}

class _ConnectionEditorSheetState extends State<_ConnectionEditorSheet> {
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
  var _loaded = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _host = TextEditingController(text: e?.host ?? '127.0.0.1');
    final d = e?.displayNumber ?? displayFromPort(e?.port ?? 5900) ?? 0;
    _display = TextEditingController(text: '$d');
    _port = TextEditingController(text: '${e?.port ?? 5900}');
    _name = TextEditingController(text: e?.displayName ?? '');
    _username = TextEditingController(text: e?.username ?? '');
    _password = TextEditingController();
    _tags = TextEditingController(text: e?.tags.join(', ') ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _preferVencrypt = e?.preferVencrypt ?? false;
    _acceptInvalidCerts = e?.acceptInvalidCerts ?? false;
    _savePassword = e != null;
    _loadPassword();
  }

  Future<void> _loadPassword() async {
    final id = widget.existing?.id;
    if (id == null) {
      setState(() => _loaded = true);
      return;
    }
    try {
      final pwd = await widget.credentials.readPassword(id);
      if (pwd != null && mounted) {
        _password.text = pwd;
      }
    } on CredentialStoreException {
      // Leave password field empty; user can re-enter.
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
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
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? 5900;
    final id = sessionKey(host, port);
    return {
      'id': id,
      'host': host,
      'port': port,
      'display_number': displayFromPort(port),
      'display_name':
          _name.text.trim().isEmpty ? null : _name.text.trim(),
      'username':
          _username.text.trim().isEmpty ? null : _username.text.trim(),
      'prefer_vencrypt': _preferVencrypt,
      'accept_invalid_certs': _acceptInvalidCerts,
      'view_only': widget.existing?.viewOnly ?? false,
      'tags': _tags.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList(),
      if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
      if (widget.existing?.thumbPath != null)
        'thumb_path': widget.existing!.thumbPath,
      if (widget.existing?.lastConnectedAt != null)
        'last_connected_at': widget.existing!.lastConnectedAt,
    };
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
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final isEdit = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isEdit ? 'Edit connection' : 'New connection',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Display name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _host,
              decoration: const InputDecoration(labelText: 'Hostname'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _display,
                    decoration: const InputDecoration(labelText: 'Display (:N)'),
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
                    decoration: const InputDecoration(labelText: 'TCP port'),
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
            TextField(
              controller: _username,
              decoration: const InputDecoration(
                labelText: 'Username (optional)',
                helperText: 'Required for Unix Login / some servers',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Password (optional)',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            CheckboxListTile(
              value: _savePassword,
              onChanged: (v) => setState(() => _savePassword = v ?? false),
              title: const Text('Save password locally'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 8),
            Text('Security', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            MaterialBanner(
              content: const Text(
                'VeNCrypt/TLS is used when the server supports it.',
              ),
              leading: const Icon(Icons.lock_outline),
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              actions: const [SizedBox.shrink()],
            ),
            SwitchListTile(
              value: _preferVencrypt,
              onChanged: (v) => setState(() => _preferVencrypt = v),
              title: const Text('Prefer VeNCrypt/TLS'),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              value: _acceptInvalidCerts,
              onChanged: (v) => setState(() => _acceptInvalidCerts = v),
              title: const Text('Accept invalid certificates'),
              subtitle: const Text('Lab use only — disables verification'),
              contentPadding: EdgeInsets.zero,
            ),
            if (_acceptInvalidCerts)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: MaterialBanner(
                  content: const Text(
                    'Certificate verification is disabled. Use only on trusted lab networks.',
                  ),
                  leading: Icon(
                    Icons.warning_amber,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  backgroundColor:
                      Theme.of(context).colorScheme.errorContainer,
                  actions: const [SizedBox.shrink()],
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _tags,
              decoration: const InputDecoration(
                labelText: 'Tags (comma-separated)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                if (isEdit)
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _submit(connect: false),
                      child: const Text('Save'),
                    ),
                  ),
                if (!isEdit || widget.connectOnSave) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _submit(connect: true),
                      child: const Text('Connect'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
