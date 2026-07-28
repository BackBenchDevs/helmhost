import 'package:flutter/services.dart';

/// Local viewer shortcut kind (keys are not forwarded to the remote).
enum SessionLocalShortcut {
  /// Push local clipboard → remote (ClientCutText).
  pasteToRemote,

  /// Swallow Cmd/Super+C/X — copy/cut use remote OS shortcuts + RFB
  /// clipboard sync (ServerCutText → local clipboard). Swallowing prevents
  /// Super+C from typing "c" on Linux remotes.
  consume,
}

/// Classify a key-down as a local viewer shortcut, or null to forward RFB.
///
/// Local chords apply even under exclusive grab (TigerVNC): status-bar Paste is
/// not the only host→remote path. Native grab reports the same chords via
/// `localShortcut`; this classifier is used by the Flutter key path.
///
/// - **⌘V** (Meta+V): paste local → remote
/// - **Shift+Insert**: paste local → remote (X11 / Windows)
/// - **Ctrl+Alt+V**: paste local → remote (Windows viewer chord; not bare Ctrl+V)
/// - **⌘C / ⌘X**: consume locally (do not send)
/// - **Ctrl+C / Ctrl+V / Ctrl+Shift+C**: always forward to remote
bool isSessionLocalShortcut({
  required LogicalKeyboardKey key,
  required bool shift,
  required bool control,
  required bool meta,
  bool alt = false,
  bool exclusiveGrab = false,
}) =>
    classifySessionLocalShortcut(
      key: key,
      shift: shift,
      control: control,
      meta: meta,
      alt: alt,
      exclusiveGrab: exclusiveGrab,
    ) !=
    null;

SessionLocalShortcut? classifySessionLocalShortcut({
  required LogicalKeyboardKey key,
  required bool shift,
  required bool control,
  required bool meta,
  bool alt = false,
  bool exclusiveGrab = false,
}) {
  // [exclusiveGrab] kept for API compat; local paste/consume still apply.
  // ignore: unused_parameter
  exclusiveGrab;

  // Ctrl+Alt+V — viewer paste (Windows); not bare Control chords.
  if (control && alt && !meta && !shift && key == LogicalKeyboardKey.keyV) {
    return SessionLocalShortcut.pasteToRemote;
  }

  // Never steal bare Control chords — those are for the remote (terminals, etc.).
  if (control && !meta) return null;

  if (meta && key == LogicalKeyboardKey.keyV) {
    return SessionLocalShortcut.pasteToRemote;
  }
  if (key == LogicalKeyboardKey.insert && shift && !meta) {
    return SessionLocalShortcut.pasteToRemote;
  }
  if (meta &&
      (key == LogicalKeyboardKey.keyC || key == LogicalKeyboardKey.keyX)) {
    return SessionLocalShortcut.consume;
  }
  return null;
}

SessionLocalShortcut? classifySessionLocalKeyEvent(
  KeyEvent event, {
  bool exclusiveGrab = false,
}) {
  if (event is! KeyDownEvent) return null;
  final keys = HardwareKeyboard.instance.logicalKeysPressed;
  final shift = keys.contains(LogicalKeyboardKey.shiftLeft) ||
      keys.contains(LogicalKeyboardKey.shiftRight);
  final control = keys.contains(LogicalKeyboardKey.controlLeft) ||
      keys.contains(LogicalKeyboardKey.controlRight);
  final meta = keys.contains(LogicalKeyboardKey.metaLeft) ||
      keys.contains(LogicalKeyboardKey.metaRight) ||
      keys.contains(LogicalKeyboardKey.meta) ||
      keys.contains(LogicalKeyboardKey.superKey);
  final alt = keys.contains(LogicalKeyboardKey.altLeft) ||
      keys.contains(LogicalKeyboardKey.altRight) ||
      keys.contains(LogicalKeyboardKey.alt);
  return classifySessionLocalShortcut(
    key: event.logicalKey,
    shift: shift,
    control: control,
    meta: meta,
    alt: alt,
    exclusiveGrab: exclusiveGrab,
  );
}

/// Back-compat name used by older call sites / tests.
bool isPasteToRemoteShortcut({
  required LogicalKeyboardKey key,
  required bool shift,
  required bool control,
  required bool meta,
  bool alt = false,
}) =>
    classifySessionLocalShortcut(
      key: key,
      shift: shift,
      control: control,
      meta: meta,
      alt: alt,
    ) ==
    SessionLocalShortcut.pasteToRemote;

bool isPasteToRemoteKeyEvent(KeyEvent event) =>
    classifySessionLocalKeyEvent(event) == SessionLocalShortcut.pasteToRemote;
