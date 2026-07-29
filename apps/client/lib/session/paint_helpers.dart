import 'package:flutter/gestures.dart';

export 'fb_texture.dart' show DamageRect, unionDamage;

/// Move coalescing interval — independent of Flutter paint frames.
const Duration kPointerFlushInterval = Duration(milliseconds: 4);

/// RFB PointerEvent button mask bits (RFB §7.5.5).
const int kRfbButtonLeft = 0x01;
const int kRfbButtonMiddle = 0x02;
const int kRfbButtonRight = 0x04;

/// Map Flutter [PointerEvent.buttons] to RFB button mask.
///
/// Flutter uses secondary=`0x02` for right and tertiary=`0x04` for middle;
/// RFB swaps those two bits. Scroll/extra bits (already RFB-shaped from the
/// wheel path) are passed through unchanged.
int flutterButtonsToRfb(int flutterButtons) {
  var rfb = flutterButtons &
      ~(kPrimaryButton | kSecondaryButton | kTertiaryButton);
  if ((flutterButtons & kPrimaryButton) != 0) rfb |= kRfbButtonLeft;
  if ((flutterButtons & kTertiaryButton) != 0) rfb |= kRfbButtonMiddle;
  if ((flutterButtons & kSecondaryButton) != 0) rfb |= kRfbButtonRight;
  return rfb;
}

/// Whether a pointer event must flush immediately (button edge) vs coalesce.
bool shouldFlushPointerImmediate({
  required int buttons,
  required int lastButtons,
}) =>
    buttons != lastButtons;

/// Whether Dart full-frame decode fallback should run.
bool shouldFallbackToDartDecode({
  required bool embedded,
  required bool hadTextureSuccess,
  required bool presentOk,
  required int failStreak,
  int failLimit = 3,
}) {
  if (presentOk) return false;
  if (embedded && hadTextureSuccess) return false;
  if (hadTextureSuccess && failStreak < failLimit) return false;
  return true;
}
