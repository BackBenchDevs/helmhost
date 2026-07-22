/// Cross-window IPC between Hub and Session (desktop_multi_window).
library;

import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';

const kMethodSessionEnded = 'session_ended';
const kMethodSessionReplaced = 'session_replaced';
const kMethodWindowClose = 'window_close';
/// Close the session Flutter window but keep the native RFB session (attach→tabs).
const kMethodWindowDismissKeepSession = 'window_dismiss_keep_session';

/// Hooks for the active session window engine (set by [SessionPage]).
class SessionWindowCommands {
  SessionWindowCommands._();

  /// Soft-close UI window; leave RFB alive for hub tab reparent.
  static Future<void> Function()? dismissKeepSession;
}
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

/// Stop the poll loop after this event (dead native id / disconnect).
bool shouldStopPollingOnEvent(Map<String, dynamic> ev) {
  if (isStaleSessionEvent(ev)) return true;
  final type = ev['type'] as String? ?? '';
  if (type != 'error') return false;
  final msg = (ev['message'] as String? ?? '').toLowerCase();
  return msg.contains('unknown session');
}

/// Prefer not notifying hub for unknown-session from an embedded tab poll.
bool isUnknownSessionMessage(String msg) =>
    msg.toLowerCase().contains('unknown session');

/// Whether disconnect should auto-start reconnect without a dialog.
///
/// Embedded + unknown session stays dialog-driven so the tab chip is kept.
bool shouldAutoReconnect({
  required bool prefEnabled,
  required bool embedded,
  required bool unknownSession,
}) {
  if (!prefEnabled) return false;
  if (embedded && unknownSession) return false;
  return true;
}
