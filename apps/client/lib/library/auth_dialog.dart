import 'package:flutter/material.dart';

import '../session_helpers.dart';

class AuthDialogResult {
  const AuthDialogResult({
    this.username,
    this.password,
    this.savePermanently = false,
  });

  final String? username;
  final String? password;
  final bool savePermanently;
}

Future<AuthDialogResult?> showAuthDialog(
  BuildContext context, {
  required AuthNeed need,
  String? initialUsername,
  String? connectingTo,
  bool defaultSavePermanently = false,
}) {
  return showDialog<AuthDialogResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _AuthDialog(
      need: need,
      initialUsername: initialUsername,
      connectingTo: connectingTo,
      defaultSavePermanently: defaultSavePermanently,
    ),
  );
}

class _AuthDialog extends StatefulWidget {
  const _AuthDialog({
    required this.need,
    this.initialUsername,
    this.connectingTo,
    this.defaultSavePermanently = false,
  });

  final AuthNeed need;
  final String? initialUsername;
  final String? connectingTo;
  final bool defaultSavePermanently;

  @override
  State<_AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<_AuthDialog> {
  late final TextEditingController _user;
  final _pass = TextEditingController();
  late bool _savePermanently;
  var _obscure = true;

  @override
  void initState() {
    super.initState();
    _user = TextEditingController(text: widget.initialUsername ?? '');
    _savePermanently = widget.defaultSavePermanently;
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needUser = widget.need == AuthNeed.usernamePassword;
    final target = widget.connectingTo;
    return AlertDialog(
      title: const Text('Authentication'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (target != null && target.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Connecting to $target',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            if (needUser)
              TextField(
                controller: _user,
                decoration: const InputDecoration(
                  labelText: 'Username',
                ),
                autofocus: true,
              ),
            if (needUser) const SizedBox(height: 12),
            TextField(
              controller: _pass,
              obscureText: _obscure,
              autofocus: !needUser,
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Remember on this device'),
              value: _savePermanently,
              onChanged: (v) => setState(() => _savePermanently = v ?? false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('OK')),
      ],
    );
  }

  void _submit() {
    Navigator.pop(
      context,
      AuthDialogResult(
        username: _user.text.trim().isEmpty ? null : _user.text.trim(),
        password: _pass.text.isEmpty ? null : _pass.text,
        savePermanently: _savePermanently,
      ),
    );
  }
}
