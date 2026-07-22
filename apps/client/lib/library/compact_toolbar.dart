import 'package:flutter/material.dart';

/// Dense address row under the Chrome-style tab strip (WF-05).
class CompactToolbar extends StatelessWidget {
  const CompactToolbar({
    super.key,
    required this.controller,
    required this.onConnect,
    this.enabled = true,
    this.errorText,
    this.hintText = 'VNC address or search…',
  });

  final TextEditingController controller;
  final VoidCallback onConnect;
  final bool enabled;
  final String? errorText;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Row(
          children: [
            Icon(Icons.lan_outlined, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: hintText,
                  errorText: errorText,
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onSubmitted: (_) => onConnect(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: enabled ? onConnect : null,
              child: const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }
}
