/// Connection bandwidth / encoding preference (ZRLE-safe presets).
enum BandwidthPreset { lan, balanced, low }

extension BandwidthPresetX on BandwidthPreset {
  String get label => switch (this) {
        BandwidthPreset.lan => 'LAN',
        BandwidthPreset.balanced => 'Balanced',
        BandwidthPreset.low => 'Low bandwidth',
      };

  String get prefsKey => switch (this) {
        BandwidthPreset.lan => 'lan',
        BandwidthPreset.balanced => 'balanced',
        BandwidthPreset.low => 'low',
      };

  /// Wire value for FFI `hh_connect` / registry JSON.
  int get wireCode => switch (this) {
        BandwidthPreset.lan => 0,
        BandwidthPreset.balanced => 1,
        BandwidthPreset.low => 2,
      };

  static BandwidthPreset fromPrefs(String? v) {
    switch (v) {
      case 'lan':
        return BandwidthPreset.lan;
      case 'low':
        return BandwidthPreset.low;
      default:
        return BandwidthPreset.balanced;
    }
  }

  static BandwidthPreset? fromLabel(String label) {
    for (final p in BandwidthPreset.values) {
      if (p.label == label) return p;
    }
    return null;
  }

  static BandwidthPreset fromWire(int code) {
    switch (code) {
      case 0:
        return BandwidthPreset.lan;
      case 2:
        return BandwidthPreset.low;
      default:
        return BandwidthPreset.balanced;
    }
  }
}

/// Clamp Tight quality/compress to RFB 0–9 range.
int clampEncodingLevel(int level) => level.clamp(0, 9);
