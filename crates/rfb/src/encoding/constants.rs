//! Encoding ID constants and diagnostics (single source of truth).

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

/// Encodings we advertise. Pseudo-encodings must be listed or DesktopSize/LastRect
/// are never sent. ExtendedDesktopSize enables TigerVNC/RealVNC RemoteResize.
/// ZRLE first among pixel encodings for bandwidth.
pub fn preferred_encodings() -> [i32; 6] {
    [
        ENC_ZRLE,
        ENC_RAW,
        ENC_COPYRECT,
        ENC_DESKTOP_SIZE,
        ENC_EXTENDED_DESKTOP_SIZE,
        ENC_LAST_RECT,
    ]
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
        _ => "unknown",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preferred_includes_zrle_first() {
        let e = preferred_encodings();
        assert_eq!(e[0], ENC_ZRLE);
        assert!(e.contains(&ENC_RAW));
        assert!(e.contains(&ENC_LAST_RECT));
        assert!(e.contains(&ENC_EXTENDED_DESKTOP_SIZE));
    }

    #[test]
    fn names_known_ids() {
        assert_eq!(encoding_name(ENC_TIGHT), "Tight");
        assert_eq!(encoding_name(ENC_CURSOR), "Cursor");
        assert_eq!(encoding_name(999), "unknown");
    }
}
