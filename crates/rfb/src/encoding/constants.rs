//! Encoding ID constants, bandwidth presets, and diagnostics (single source of truth).

pub const ENC_RAW: i32 = 0;
pub const ENC_COPYRECT: i32 = 1;
pub const ENC_RRE: i32 = 2;
pub const ENC_HEXTILE: i32 = 5;
pub const ENC_TIGHT: i32 = 7;
pub const ENC_TRLE: i32 = 15;
pub const ENC_ZRLE: i32 = 16;
pub const ENC_JPEG: i32 = 21;
pub const ENC_DESKTOP_SIZE: i32 = -223;
pub const ENC_LAST_RECT: i32 = -224;
pub const ENC_CURSOR: i32 = -239;
pub const ENC_XCURSOR: i32 = -240;
pub const ENC_EXTENDED_DESKTOP_SIZE: i32 = -308;
/// TigerVNC Continuous Updates capability (pseudo-encoding).
pub const ENC_CONTINUOUS_UPDATES: i32 = -313;

/// Tight quality pseudo-encoding range: -32 (lowest) .. -23 (highest).
const TIGHT_QUALITY_BASE: i32 = -32;
/// Tight compress-level pseudo-encoding range: -256 (none) .. -247 (max).
const TIGHT_COMPRESS_BASE: i32 = -256;

/// Connection bandwidth profile used to select advertised encodings.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum BandwidthPreset {
    /// Local LAN / high bandwidth — Tight + ZRLE + Raw.
    Lan,
    /// Balanced default — Tight-first like TigerVNC.
    #[default]
    Balanced,
    /// Low bandwidth — Tight + ZRLE, no Raw.
    Low,
}

/// Default advertised encodings (Balanced preset).
pub fn preferred_encodings() -> Vec<i32> {
    preferred_encodings_for(BandwidthPreset::Balanced)
}

/// Advertised encodings for a given bandwidth profile.
///
/// - `Lan` / `Balanced`: Tight, ZRLE, Raw, CopyRect, DesktopSize, ExtDesktopSize, LastRect, CU
/// - `Low`: Tight, ZRLE, CopyRect, DesktopSize, ExtDesktopSize, LastRect, CU (no Raw)
pub fn preferred_encodings_for(preset: BandwidthPreset) -> Vec<i32> {
    match preset {
        BandwidthPreset::Lan | BandwidthPreset::Balanced => vec![
            ENC_TIGHT,
            ENC_ZRLE,
            ENC_RAW,
            ENC_COPYRECT,
            ENC_DESKTOP_SIZE,
            ENC_EXTENDED_DESKTOP_SIZE,
            ENC_LAST_RECT,
            ENC_CONTINUOUS_UPDATES,
        ],
        BandwidthPreset::Low => vec![
            ENC_TIGHT,
            ENC_ZRLE,
            ENC_COPYRECT,
            ENC_DESKTOP_SIZE,
            ENC_EXTENDED_DESKTOP_SIZE,
            ENC_LAST_RECT,
            ENC_CONTINUOUS_UPDATES,
        ],
    }
}

/// Tight quality pseudo-encoding for the given level (0 = lowest, 9 = highest).
/// Maps to the range -32 .. -23.
pub fn quality_level_encoding(level: i32) -> i32 {
    TIGHT_QUALITY_BASE + level.clamp(0, 9)
}

/// Tight compress-level pseudo-encoding for the given level (0 = none, 9 = maximum).
/// Maps to the range -256 .. -247.
pub fn compress_level_encoding(level: i32) -> i32 {
    TIGHT_COMPRESS_BASE + level.clamp(0, 9)
}

/// Build a full encoding list optionally including Tight quality / compress pseudo-encodings.
///
/// When either `quality` or `compress` is `Some`, Tight is ensured first and
/// the corresponding pseudo-encodings are appended.
pub fn encodings_with_quality_compress(
    preset: BandwidthPreset,
    quality: Option<i32>,
    compress: Option<i32>,
) -> Vec<i32> {
    let mut encs = preferred_encodings_for(preset);

    if quality.is_some() || compress.is_some() {
        encs.retain(|&e| e != ENC_TIGHT);
        encs.insert(0, ENC_TIGHT);
        if let Some(q) = quality {
            encs.push(quality_level_encoding(q));
        }
        if let Some(c) = compress {
            encs.push(compress_level_encoding(c));
        }
    }

    encs
}

/// Human-readable name for common RFB encoding IDs (diagnostics).
pub fn encoding_name(enc: i32) -> &'static str {
    match enc {
        ENC_RAW => "Raw",
        ENC_COPYRECT => "CopyRect",
        ENC_RRE => "RRE",
        4 => "CoRRE",
        ENC_HEXTILE => "Hextile",
        ENC_TIGHT => "Tight",
        ENC_TRLE => "TRLE",
        ENC_ZRLE => "ZRLE",
        ENC_JPEG => "JPEG",
        ENC_DESKTOP_SIZE => "DesktopSize",
        ENC_LAST_RECT => "LastRect",
        ENC_CURSOR => "Cursor",
        ENC_XCURSOR => "XCursor",
        ENC_EXTENDED_DESKTOP_SIZE => "ExtendedDesktopSize",
        ENC_CONTINUOUS_UPDATES => "ContinuousUpdates",
        _ => "unknown",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preferred_balanced_tight_first_with_cu() {
        let e = preferred_encodings();
        assert_eq!(e[0], ENC_TIGHT);
        assert!(e.contains(&ENC_ZRLE));
        assert!(e.contains(&ENC_RAW));
        assert!(e.contains(&ENC_CONTINUOUS_UPDATES));
        assert!(e.contains(&ENC_LAST_RECT));
    }

    #[test]
    fn preferred_lan_same_as_balanced() {
        assert_eq!(
            preferred_encodings_for(BandwidthPreset::Lan),
            preferred_encodings_for(BandwidthPreset::Balanced)
        );
    }

    #[test]
    fn preferred_low_tight_first_no_raw() {
        let e = preferred_encodings_for(BandwidthPreset::Low);
        assert_eq!(e[0], ENC_TIGHT);
        assert!(!e.contains(&ENC_RAW), "Low preset must not include Raw");
        assert!(e.contains(&ENC_ZRLE));
        assert!(e.contains(&ENC_CONTINUOUS_UPDATES));
    }

    #[test]
    fn quality_level_range() {
        assert_eq!(quality_level_encoding(0), -32);
        assert_eq!(quality_level_encoding(9), -23);
        assert_eq!(quality_level_encoding(8), -24);
        assert_eq!(quality_level_encoding(-5), -32);
        assert_eq!(quality_level_encoding(99), -23);
    }

    #[test]
    fn compress_level_range() {
        assert_eq!(compress_level_encoding(0), -256);
        assert_eq!(compress_level_encoding(2), -254);
        assert_eq!(compress_level_encoding(9), -247);
    }

    #[test]
    fn encodings_with_quality_inserts_tight_first() {
        let e = encodings_with_quality_compress(BandwidthPreset::Balanced, Some(8), Some(2));
        assert_eq!(e[0], ENC_TIGHT);
        assert!(e.contains(&quality_level_encoding(8)));
        assert!(e.contains(&compress_level_encoding(2)));
        assert_eq!(
            e.iter().filter(|&&x| x == ENC_TIGHT).count(),
            1,
            "Tight must appear exactly once"
        );
    }

    #[test]
    fn names_known_ids() {
        assert_eq!(encoding_name(ENC_TIGHT), "Tight");
        assert_eq!(encoding_name(ENC_CONTINUOUS_UPDATES), "ContinuousUpdates");
        assert_eq!(encoding_name(999), "unknown");
    }
}
