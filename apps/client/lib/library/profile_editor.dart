import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logging/logger.dart';
import '../session_helpers.dart';
import '../storage/credential_store.dart';

class ProfileEditorResult {
  const ProfileEditorResult({
    required this.profile,
    this.password,
    required this.savePassword,
    this.clearPassword = false,
  });

  final ConnectionProfileCard profile;
  final String? password;
  final bool savePassword;
  final bool clearPassword;
}

Future<ProfileEditorResult?> showProfileEditor(
  BuildContext context, {
  ConnectionProfileCard? existing,
  required ICredentialStore credentials,
  VoidCallback? onAddConnection,
}) {
  return showDialog<ProfileEditorResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ProfileEditorDialog(
      existing: existing,
      credentials: credentials,
      onAddConnection: onAddConnection,
    ),
  );
}

class _ProfileEditorDialog extends StatefulWidget {
  const _ProfileEditorDialog({
    this.existing,
    required this.credentials,
    this.onAddConnection,
  });

  final ConnectionProfileCard? existing;
  final ICredentialStore credentials;
  final VoidCallback? onAddConnection;

  @override
  State<_ProfileEditorDialog> createState() => _ProfileEditorDialogState();
}

class _ProfileEditorDialogState extends State<_ProfileEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _domain;
  late final TextEditingController _notes;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _display;
  var _preferVencrypt = false;
  var _acceptInvalidCerts = false;
  var _viewOnly = false;
  var _savePassword = false;
  var _obscure = true;
  var _loaded = false;
  String? _error;
  String? _lastAutoName;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _domain = TextEditingController(text: e?.domain ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _username = TextEditingController(text: e?.defaultUsername ?? '');
    _password = TextEditingController();
    _display = TextEditingController(
      text: e?.defaultDisplay?.toString() ?? '',
    );
    _preferVencrypt = e?.preferVencrypt ?? false;
    _acceptInvalidCerts = e?.acceptInvalidCerts ?? false;
    _viewOnly = e?.viewOnly ?? false;
    _savePassword = e != null;
    if (e == null && _domain.text.isNotEmpty) {
      _lastAutoName = suggestProfileNameFromDomain(_domain.text);
    }
    _loadPassword();
  }

  void _onDomainChanged(String _) {
    final suggested = suggestProfileNameFromDomain(_domain.text);
    final name = _name.text.trim();
    final shouldFill = name.isEmpty ||
        (_lastAutoName != null && name == _lastAutoName);
    setState(() {
      _error = null;
      if (shouldFill && suggested.isNotEmpty) {
        _name.text = suggested;
        _lastAutoName = suggested;
      }
    });
  }

  Future<void> _loadPassword() async {
    final id = widget.existing?.id;
    if (id == null) {
      setState(() => _loaded = true);
      return;
    }
    try {
      final pwd = await widget.credentials.readPassword(profileVaultKey(id));
      if (pwd != null && mounted) {
        _password.text = pwd;
      }
    } on CredentialStoreException {
      // leave empty
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _name.dispose();
    _domain.dispose();
    _notes.dispose();
    _username.dispose();
    _password.dispose();
    _display.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final domain = normalizeDomain(_domain.text);
    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    if (domain.isEmpty) {
      setState(() => _error = 'Domain is required (e.g. lab.internal)');
      return;
    }
    final rawDisplay = _display.text;
    final display = parseDefaultDisplayField(rawDisplay);
    if (rawDisplay.trim().isNotEmpty && display == null) {
      setState(() => _error = 'Default display must be 0–99');
      return;
    }
    final id = widget.existing?.id ??
        'profile-${DateTime.now().millisecondsSinceEpoch}';
    final profile = ConnectionProfileCard(
      id: id,
      name: name,
      domain: domain,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      preferVencrypt: _preferVencrypt,
      acceptInvalidCerts: _acceptInvalidCerts,
      viewOnly: _viewOnly,
      defaultUsername:
          _username.text.trim().isEmpty ? null : _username.text.trim(),
      defaultDisplay: display,
    );
    defaultLogger(module: 'profile_editor').info('profile submit', {
      'raw_display': rawDisplay,
      'parsed_display': display,
      'json': profile.toJson(),
    });
    Navigator.pop(
      context,
      ProfileEditorResult(
        profile: profile,
        password: _password.text.isEmpty ? null : _password.text,
        savePassword: _savePassword,
        clearPassword: !_savePassword,
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
        ? 'Profile — ${widget.existing!.name}'
        : 'New Profile';
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _domain,
                decoration: InputDecoration(
                  labelText: 'Domain',
                  hintText: 'lab.internal',
                  helperText: _domain.text.trim().isEmpty
                      ? 'Hosts use short names under this domain'
                      : 'Hosts connect as host.${normalizeDomain(_domain.text)}',
                  errorText: _error,
                ),
                onChanged: _onDomainChanged,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              const SizedBox(height: 12),
              Text(
                'Shared defaults',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _username,
                decoration:
                    const InputDecoration(labelText: 'Default username'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Group password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Save password for this group'),
                value: _savePassword,
                onChanged: (v) =>
                    setState(() => _savePassword = v ?? false),
              ),
              TextField(
                controller: _display,
                decoration: const InputDecoration(
                  labelText: 'Default display (:N)',
                  hintText: 'Optional',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() => _error = null),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Prefer VeNCrypt / TLS'),
                value: _preferVencrypt,
                onChanged: (v) =>
                    setState(() => _preferVencrypt = v ?? false),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Accept invalid certificates'),
                value: _acceptInvalidCerts,
                onChanged: (v) =>
                    setState(() => _acceptInvalidCerts = v ?? false),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('View only'),
                value: _viewOnly,
                onChanged: (v) => setState(() => _viewOnly = v ?? false),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.existing != null)
          TextButton(
            key: const Key('profile-add-connection'),
            onPressed: widget.onAddConnection,
            child: const Text('Add connection…'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('OK')),
      ],
    );
  }
}
