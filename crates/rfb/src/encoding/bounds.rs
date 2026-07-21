//! Framebuffer rectangle bounds (TigerVNC: "Rect too big").

use crate::encoding::constants::{ENC_DESKTOP_SIZE, ENC_EXTENDED_DESKTOP_SIZE, ENC_LAST_RECT};
use crate::messages::FramebufferRectHeader;

/// Returns true when the encoding uses rect w×h as desktop metrics, not FB damage.
pub fn is_geometry_pseudo_encoding(enc: i32) -> bool {
    matches!(
        enc,
        ENC_DESKTOP_SIZE | ENC_EXTENDED_DESKTOP_SIZE | ENC_LAST_RECT
    )
}

/// Reject damage rectangles that extend past the current framebuffer.
///
/// DesktopSize / LastRect are exempt: their w×h are not a blit region
/// (TigerVNC `CMsgReader` treats DesktopSize as a resize request).
pub fn rect_fits_framebuffer(
    fb_w: u16,
    fb_h: u16,
    hdr: &FramebufferRectHeader,
) -> Result<(), String> {
    if is_geometry_pseudo_encoding(hdr.encoding) {
        return Ok(());
    }
    let x = u32::from(hdr.x);
    let y = u32::from(hdr.y);
    let w = u32::from(hdr.w);
    let h = u32::from(hdr.h);
    let right = x.saturating_add(w);
    let bottom = y.saturating_add(h);
    if right > u32::from(fb_w) || bottom > u32::from(fb_h) {
        return Err(format!(
            "rect too big: ({},{}) {}x{} vs fb {}x{}",
            hdr.x, hdr.y, hdr.w, hdr.h, fb_w, fb_h
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::encoding::constants::{ENC_DESKTOP_SIZE, ENC_RAW};

    fn hdr(x: u16, y: u16, w: u16, h: u16, encoding: i32) -> FramebufferRectHeader {
        FramebufferRectHeader {
            x,
            y,
            w,
            h,
            encoding,
        }
    }

    #[test]
    fn damage_inside_ok() {
        assert!(rect_fits_framebuffer(100, 80, &hdr(10, 10, 20, 20, ENC_RAW)).is_ok());
    }

    #[test]
    fn damage_past_edge_errs() {
        assert!(rect_fits_framebuffer(100, 80, &hdr(90, 0, 20, 10, ENC_RAW)).is_err());
    }

    #[test]
    fn desktop_size_exempt() {
        assert!(rect_fits_framebuffer(100, 80, &hdr(0, 0, 1920, 1080, ENC_DESKTOP_SIZE)).is_ok());
    }

    #[test]
    fn zero_area_at_origin_ok() {
        assert!(rect_fits_framebuffer(100, 80, &hdr(0, 0, 0, 0, ENC_RAW)).is_ok());
    }
}
