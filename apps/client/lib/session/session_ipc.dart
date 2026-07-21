/// Cross-window IPC between Hub and Session (desktop_multi_window).
library;

import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';

const kMethodSessionEnded = 'session_ended';
const kMethodSessionReplaced = 'session_replaced';
const kMethodWindowClose = 'window_close';

/// Notify the Hub window (non-session). Best-effort; ignores failures.
Future<void> notifyHub(String method, [Map<String, dynamic>? arguments]) async {
  final hub = await findHubController();
  if (hub == null) return;
  try {
    await hub.invokeMethod<void>(method, arguments);
  } catch (_) {}
}

Future<WindowController?> findHubController() async {
  for (final c in await WindowController.getAll()) {
    final raw = c.arguments.trim();
    if (raw.isEmpty) return c;
    try {
      final a = jsonDecode(raw) as Map<String, dynamic>;
      final role = a['role'] as String? ?? 'hub';
      if (role != 'session') return c;
    } catch (_) {
      return c;
    }
  }
  return null;
}

/// True when poll JSON means the native session is gone or ending.
bool isStaleSessionEvent(Map<String, dynamic> ev) {
  final type = ev['type'] as String? ?? '';
  if (type == 'disconnected') return true;
  if (type == 'error') {
    final msg = (ev['message'] as String? ?? '').toLowerCase();
    return msg.contains('unknown session') || msg.contains('disconnected');
  }
  return false;
}
