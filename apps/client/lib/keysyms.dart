import 'package:flutter/services.dart';

const int xkControlL = 0xffe3;
const int xkControlR = 0xffe4;

/// X11 keysym for a printable Unicode character (Latin-1 or Unicode plane).
int charToKeysym(String ch) {
  if (ch.isEmpty) return 0;
  final u = ch.codeUnitAt(0);
  if (u >= 0x20 && u <= 0x7e) return u;
  if (u >= 0xa0 && u <= 0xff) return u;
  return 0x01000000 | u;
}

/// Map a Flutter [LogicalKeyboardKey] to an X11 keysym (no character).
///
/// macOS Cmd → Super (TigerVNC RuVNC / not remapped to Control). Physical
/// Control stays Control so terminal Ctrl+C works on the remote.
int? logicalKeyToKeysym(LogicalKeyboardKey key) {
  // Modifiers
  if (key == LogicalKeyboardKey.shiftLeft) return 0xffe1;
  if (key == LogicalKeyboardKey.shiftRight) return 0xffe2;
  if (key == LogicalKeyboardKey.controlLeft) return xkControlL;
  if (key == LogicalKeyboardKey.controlRight) return xkControlR;
  if (key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.meta ||
      key == LogicalKeyboardKey.superKey) {
    return 0xffeb; // XK_Super_L
  }
  if (key == LogicalKeyboardKey.metaRight) return 0xffec;
  if (key == LogicalKeyboardKey.altLeft) return 0xffe9;
  if (key == LogicalKeyboardKey.altRight) return 0xffea;
  if (key == LogicalKeyboardKey.altGraph) return 0xfe03; // ISO_Level3_Shift

  // Navigation / editing
  if (key == LogicalKeyboardKey.escape) return 0xff1b;
  if (key == LogicalKeyboardKey.tab) return 0xff09;
  if (key == LogicalKeyboardKey.backspace) return 0xff08;
  if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
    return 0xff0d;
  }
  if (key == LogicalKeyboardKey.space) return 0x0020;
  if (key == LogicalKeyboardKey.insert) return 0xff63;
  if (key == LogicalKeyboardKey.delete) return 0xffff;
  if (key == LogicalKeyboardKey.home) return 0xff50;
  if (key == LogicalKeyboardKey.end) return 0xff57;
  if (key == LogicalKeyboardKey.pageUp) return 0xff55;
  if (key == LogicalKeyboardKey.pageDown) return 0xff56;
  if (key == LogicalKeyboardKey.arrowLeft) return 0xff51;
  if (key == LogicalKeyboardKey.arrowUp) return 0xff52;
  if (key == LogicalKeyboardKey.arrowRight) return 0xff53;
  if (key == LogicalKeyboardKey.arrowDown) return 0xff54;

  // Function keys
  if (key == LogicalKeyboardKey.f1) return 0xffbe;
  if (key == LogicalKeyboardKey.f2) return 0xffbf;
  if (key == LogicalKeyboardKey.f3) return 0xffc0;
  if (key == LogicalKeyboardKey.f4) return 0xffc1;
  if (key == LogicalKeyboardKey.f5) return 0xffc2;
  if (key == LogicalKeyboardKey.f6) return 0xffc3;
  if (key == LogicalKeyboardKey.f7) return 0xffc4;
  if (key == LogicalKeyboardKey.f8) return 0xffc5;
  if (key == LogicalKeyboardKey.f9) return 0xffc6;
  if (key == LogicalKeyboardKey.f10) return 0xffc7;
  if (key == LogicalKeyboardKey.f11) return 0xffc8;
  if (key == LogicalKeyboardKey.f12) return 0xffc9;

  // Letters (unshifted Latin-1) — prefer [keysymForKeyEvent] with character
  if (key == LogicalKeyboardKey.keyA) return 0x0061;
  if (key == LogicalKeyboardKey.keyB) return 0x0062;
  if (key == LogicalKeyboardKey.keyC) return 0x0063;
  if (key == LogicalKeyboardKey.keyD) return 0x0064;
  if (key == LogicalKeyboardKey.keyE) return 0x0065;
  if (key == LogicalKeyboardKey.keyF) return 0x0066;
  if (key == LogicalKeyboardKey.keyG) return 0x0067;
  if (key == LogicalKeyboardKey.keyH) return 0x0068;
  if (key == LogicalKeyboardKey.keyI) return 0x0069;
  if (key == LogicalKeyboardKey.keyJ) return 0x006a;
  if (key == LogicalKeyboardKey.keyK) return 0x006b;
  if (key == LogicalKeyboardKey.keyL) return 0x006c;
  if (key == LogicalKeyboardKey.keyM) return 0x006d;
  if (key == LogicalKeyboardKey.keyN) return 0x006e;
  if (key == LogicalKeyboardKey.keyO) return 0x006f;
  if (key == LogicalKeyboardKey.keyP) return 0x0070;
  if (key == LogicalKeyboardKey.keyQ) return 0x0071;
  if (key == LogicalKeyboardKey.keyR) return 0x0072;
  if (key == LogicalKeyboardKey.keyS) return 0x0073;
  if (key == LogicalKeyboardKey.keyT) return 0x0074;
  if (key == LogicalKeyboardKey.keyU) return 0x0075;
  if (key == LogicalKeyboardKey.keyV) return 0x0076;
  if (key == LogicalKeyboardKey.keyW) return 0x0077;
  if (key == LogicalKeyboardKey.keyX) return 0x0078;
  if (key == LogicalKeyboardKey.keyY) return 0x0079;
  if (key == LogicalKeyboardKey.keyZ) return 0x007a;

  if (key == LogicalKeyboardKey.digit0) return 0x0030;
  if (key == LogicalKeyboardKey.digit1) return 0x0031;
  if (key == LogicalKeyboardKey.digit2) return 0x0032;
  if (key == LogicalKeyboardKey.digit3) return 0x0033;
  if (key == LogicalKeyboardKey.digit4) return 0x0034;
  if (key == LogicalKeyboardKey.digit5) return 0x0035;
  if (key == LogicalKeyboardKey.digit6) return 0x0036;
  if (key == LogicalKeyboardKey.digit7) return 0x0037;
  if (key == LogicalKeyboardKey.digit8) return 0x0038;
  if (key == LogicalKeyboardKey.digit9) return 0x0039;

  if (key == LogicalKeyboardKey.minus) return 0x002d;
  if (key == LogicalKeyboardKey.equal) return 0x003d;
  if (key == LogicalKeyboardKey.bracketLeft) return 0x005b;
  if (key == LogicalKeyboardKey.bracketRight) return 0x005d;
  if (key == LogicalKeyboardKey.backslash) return 0x005c;
  if (key == LogicalKeyboardKey.semicolon) return 0x003b;
  if (key == LogicalKeyboardKey.quote) return 0x0027;
  if (key == LogicalKeyboardKey.comma) return 0x002c;
  if (key == LogicalKeyboardKey.period) return 0x002e;
  if (key == LogicalKeyboardKey.slash) return 0x002f;
  if (key == LogicalKeyboardKey.backquote) return 0x0060;

  return null;
}

/// Resolve keysym for a Flutter [KeyEvent].
///
/// Prefer [KeyEvent.character] for printables (correct Shift+letter);
/// otherwise use the logical-key table. With Control held, prefer the base
/// letter keysym so Ctrl+C is not lost to a capitalized character path.
int? keysymForKeyEvent(KeyEvent event) {
  final logical = logicalKeyToKeysym(event.logicalKey);
  // Modifiers / nav / F-keys: always use table (character is often empty/wrong)
  if (logical != null && logical >= 0xff00) {
    return logical;
  }

  final keys = HardwareKeyboard.instance.logicalKeysPressed;
  final controlHeld = keys.contains(LogicalKeyboardKey.controlLeft) ||
      keys.contains(LogicalKeyboardKey.controlRight);

  if (controlHeld && logical != null) {
    return logical;
  }

  final ch = event.character;
  if (ch != null && ch.isNotEmpty) {
    final sym = charToKeysym(ch);
    if (sym != 0) return sym;
  }
  if (logical != null) return logical;
  final label = event.logicalKey.keyLabel;
  if (label.length == 1) {
    final sym = charToKeysym(label);
    if (sym != 0) return sym;
  }
  return null;
}
