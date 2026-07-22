export 'fb_texture.dart' show DamageRect, unionDamage;

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
