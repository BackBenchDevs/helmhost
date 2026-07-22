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
/// Matches TigerVNC / RuVNC conventions:
/// - **⌘V** (Meta+V): paste local → remote
/// - **Shift+Insert**: paste local → remote (X11)
/// - **⌘C / ⌘X**: consume locally (do not send); remote copy is Ctrl(+Shift)+C
///   on the remote OS, synced via ServerCutText
/// - **Ctrl+C / Ctrl+V / Ctrl+Shift+C**: always forward to remote
bool isSessionLocalShortcut({
  required LogicalKeyboardKey key,
  required bool shift,
  required bool control,
  required bool meta,
}) =>
    classifySessionLocalShortcut(
      key: key,
      shift: shift,
      control: control,
      meta: meta,
    ) !=
    null;

SessionLocalShortcut? classifySessionLocalShortcut({
  required LogicalKeyboardKey key,
  required bool shift,
  required bool control,
  required bool meta,
}) {
  // Never steal Control chords — those are for the remote (terminals, etc.).
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

SessionLocalShortcut? classifySessionLocalKeyEvent(KeyEvent event) {
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
  return classifySessionLocalShortcut(
    key: event.logicalKey,
    shift: shift,
    control: control,
    meta: meta,
  );
}

/// Back-compat name used by older call sites / tests.
bool isPasteToRemoteShortcut({
  required LogicalKeyboardKey key,
  required bool shift,
  required bool control,
  required bool meta,
}) =>
    classifySessionLocalShortcut(
      key: key,
      shift: shift,
      control: control,
      meta: meta,
    ) ==
    SessionLocalShortcut.pasteToRemote;

bool isPasteToRemoteKeyEvent(KeyEvent event) =>
    classifySessionLocalKeyEvent(event) == SessionLocalShortcut.pasteToRemote;
