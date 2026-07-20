import 'package:flutter/material.dart';

import '../session_helpers.dart';

class AuthDialogResult {
  const AuthDialogResult({this.username, this.password});
  final String? username;
  final String? password;
}

Future<AuthDialogResult?> showAuthDialog(
  BuildContext context, {
  required AuthNeed need,
  String? initialUsername,
}) {
  return showDialog<AuthDialogResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _AuthDialog(need: need, initialUsername: initialUsername),
  );
}

class _AuthDialog extends StatefulWidget {
  const _AuthDialog({required this.need, this.initialUsername});
  final AuthNeed need;
  final String? initialUsername;

  @override
  State<_AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<_AuthDialog> {
  late final TextEditingController _user;
  final _pass = TextEditingController();

  @override
  void initState() {
    super.initState();
    _user = TextEditingController(text: widget.initialUsername ?? '');
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
    return AlertDialog(
      title: Text(needUser ? 'Sign in' : 'Password required'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (needUser)
            TextField(
              controller: _user,
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          if (needUser) const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: true,
            autofocus: !needUser,
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Connect')),
      ],
    );
  }

  void _submit() {
    Navigator.pop(
      context,
      AuthDialogResult(
        username: _user.text.trim().isEmpty ? null : _user.text.trim(),
        password: _pass.text.isEmpty ? null : _pass.text,
      ),
    );
  }
}
