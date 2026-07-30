//! Decode RFB local-cursor pseudo-encodings (TigerVNC-compatible).

use crate::pixel_format::{pixel_to_rgba, PixelFormat};

/// Max cursor edge length (TigerVNC `CMsgReader::maxCursorSize`).
pub const MAX_CURSOR_SIZE: u16 = 256;

/// Decoded local cursor shape (non-premultiplied RGBA8).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CursorShape {
    pub width: u16,
    pub height: u16,
    pub hotspot_x: u16,
    pub hotspot_y: u16,
    /// Row-major RGBA8, length `width * height * 4` (empty when invisible).
    pub rgba: Vec<u8>,
}

impl CursorShape {
    pub fn empty(hotspot_x: u16, hotspot_y: u16) -> Self {
        Self {
            width: 0,
            height: 0,
            hotspot_x,
            hotspot_y,
            rgba: Vec::new(),
        }
    }

    pub fn is_empty(&self) -> bool {
        self.width == 0 || self.height == 0 || self.rgba.is_empty()
    }
}

fn check_size(w: u16, h: u16) -> Result<(), String> {
    if w > MAX_CURSOR_SIZE || h > MAX_CURSOR_SIZE {
        return Err(format!("cursor too big: {w}x{h}"));
    }
    Ok(())
}

fn mask_bytes_per_row(w: u16) -> usize {
    (w as usize).div_ceil(8)
}

fn unpremultiply_rgba(buf: &mut [u8]) {
    for px in buf.chunks_exact_mut(4) {
        let a = px[3];
        if a == 0 {
            px[0] = 0;
            px[1] = 0;
            px[2] = 0;
            continue;
        }
        // TigerVNC: avoid div-by-zero with a==0 already handled; use a.max(1) style.
        let a_n = if a == 0 { 1u16 } else { u16::from(a) };
        px[0] = ((u16::from(px[0]) * 255) / a_n) as u8;
        px[1] = ((u16::from(px[1]) * 255) / a_n) as u8;
        px[2] = ((u16::from(px[2]) * 255) / a_n) as u8;
    }
}

/// Classic Cursor (−239): pixels in session PF + 1bpp mask. `x`/`y` = hotspot.
pub fn decode_cursor(
    pf: &PixelFormat,
    w: u16,
    h: u16,
    hotspot_x: u16,
    hotspot_y: u16,
    data: &[u8],
) -> Result<CursorShape, String> {
    check_size(w, h)?;
    if w == 0 || h == 0 {
        return Ok(CursorShape::empty(hotspot_x, hotspot_y));
    }
    let bpp = pf.bytes_per_pixel();
    let pix_len = (w as usize) * (h as usize) * bpp;
    let mask_len = mask_bytes_per_row(w) * (h as usize);
    if data.len() < pix_len + mask_len {
        return Err(format!(
            "cursor data short: {} < {}",
            data.len(),
            pix_len + mask_len
        ));
    }
    let pixels = &data[..pix_len];
    let mask = &data[pix_len..pix_len + mask_len];
    let mpr = mask_bytes_per_row(w);
    let mut rgba = Vec::with_capacity((w as usize) * (h as usize) * 4);
    for y in 0..h as usize {
        for x in 0..w as usize {
            let off = (y * (w as usize) + x) * bpp;
            let mut px = pixel_to_rgba(pf, &pixels[off..off + bpp]);
            let byte = y * mpr + x / 8;
            let bit = 7 - (x % 8);
            px[3] = if mask[byte] & (1 << bit) != 0 { 255 } else { 0 };
            rgba.extend_from_slice(&px);
        }
    }
    Ok(CursorShape {
        width: w,
        height: h,
        hotspot_x,
        hotspot_y,
        rgba,
    })
}

/// XCursor (−240): fg/bg RGB + source bitmap + mask.
pub fn decode_xcursor(
    w: u16,
    h: u16,
    hotspot_x: u16,
    hotspot_y: u16,
    data: &[u8],
) -> Result<CursorShape, String> {
    check_size(w, h)?;
    if w == 0 || h == 0 {
        return Ok(CursorShape::empty(hotspot_x, hotspot_y));
    }
    let bitmap_len = mask_bytes_per_row(w) * (h as usize);
    let need = 6 + bitmap_len * 2;
    if data.len() < need {
        return Err(format!("xcursor data short: {} < {need}", data.len()));
    }
    let pr = data[0];
    let pg = data[1];
    let pb = data[2];
    let sr = data[3];
    let sg = data[4];
    let sb = data[5];
    let src = &data[6..6 + bitmap_len];
    let mask = &data[6 + bitmap_len..6 + 2 * bitmap_len];
    let mpr = mask_bytes_per_row(w);
    let mut rgba = Vec::with_capacity((w as usize) * (h as usize) * 4);
    for y in 0..h as usize {
        for x in 0..w as usize {
            let byte = y * mpr + x / 8;
            let bit = 7 - (x % 8);
            let on = src[byte] & (1 << bit) != 0;
            let visible = mask[byte] & (1 << bit) != 0;
            if on {
                rgba.extend_from_slice(&[pr, pg, pb, if visible { 255 } else { 0 }]);
            } else {
                rgba.extend_from_slice(&[sr, sg, sb, if visible { 255 } else { 0 }]);
            }
        }
    }
    Ok(CursorShape {
        width: w,
        height: h,
        hotspot_x,
        hotspot_y,
        rgba,
    })
}

/// Byte length of CursorWithAlpha payload (nested encoding + pixels).
pub fn cursor_with_alpha_payload_len(w: u16, h: u16) -> usize {
    4 + (w as usize) * (h as usize) * 4
}

/// CursorWithAlpha (−314): nested Raw encoding + premultiplied RGBA bytes.
///
/// Wire payload starts with `encoding` (i32 BE); only Raw (0) is supported.
/// Empty cursors still carry the nested encoding dword.
pub fn decode_cursor_with_alpha(
    w: u16,
    h: u16,
    hotspot_x: u16,
    hotspot_y: u16,
    data: &[u8],
) -> Result<CursorShape, String> {
    check_size(w, h)?;
    let need = cursor_with_alpha_payload_len(w, h);
    if data.len() < need {
        return Err(format!(
            "cursorWithAlpha data short: {} < {need}",
            data.len()
        ));
    }
    let nested = i32::from_be_bytes([data[0], data[1], data[2], data[3]]);
    if nested != 0 {
        return Err(format!(
            "cursorWithAlpha nested encoding {nested} unsupported (want Raw)"
        ));
    }
    if w == 0 || h == 0 {
        return Ok(CursorShape::empty(hotspot_x, hotspot_y));
    }
    let mut rgba = data[4..need].to_vec();
    unpremultiply_rgba(&mut rgba);
    Ok(CursorShape {
        width: w,
        height: h,
        hotspot_x,
        hotspot_y,
        rgba,
    })
}

/// VMwareCursor (`WMVd`): type 0 = and/xor in PF; type 1 = RGBA.
pub fn decode_vmware_cursor(
    pf: &PixelFormat,
    w: u16,
    h: u16,
    hotspot_x: u16,
    hotspot_y: u16,
    data: &[u8],
) -> Result<CursorShape, String> {
    check_size(w, h)?;
    if w == 0 || h == 0 {
        return Ok(CursorShape::empty(hotspot_x, hotspot_y));
    }
    if data.len() < 2 {
        return Err("vmware cursor missing type".into());
    }
    let ctype = data[0];
    // data[1] = pad
    let rest = &data[2..];
    match ctype {
        0 => {
            let bpp = pf.bytes_per_pixel();
            let plane = (w as usize) * (h as usize) * bpp;
            if rest.len() < plane * 2 {
                return Err(format!(
                    "vmware and/xor short: {} < {}",
                    rest.len(),
                    plane * 2
                ));
            }
            let and_mask = &rest[..plane];
            let xor_mask = &rest[plane..plane * 2];
            let mut rgba = Vec::with_capacity((w as usize) * (h as usize) * 4);
            for i in 0..(w as usize) * (h as usize) {
                let aoff = i * bpp;
                let and_px = &and_mask[aoff..aoff + bpp];
                let xor_px = &xor_mask[aoff..aoff + bpp];
                let and_zero = and_px.iter().all(|&b| b == 0);
                let xor_zero = xor_px.iter().all(|&b| b == 0);
                if and_zero {
                    let mut c = pixel_to_rgba(pf, xor_px);
                    c[3] = 255;
                    rgba.extend_from_slice(&c);
                } else if xor_zero {
                    rgba.extend_from_slice(&[0, 0, 0, 0]);
                } else {
                    // Inverted / partial — TigerVNC falls back to opaque black.
                    rgba.extend_from_slice(&[0, 0, 0, 255]);
                }
            }
            Ok(CursorShape {
                width: w,
                height: h,
                hotspot_x,
                hotspot_y,
                rgba,
            })
        }
        1 => {
            let need = (w as usize) * (h as usize) * 4;
            if rest.len() < need {
                return Err(format!("vmware rgba short: {} < {need}", rest.len()));
            }
            Ok(CursorShape {
                width: w,
                height: h,
                hotspot_x,
                hotspot_y,
                rgba: rest[..need].to_vec(),
            })
        }
        other => Err(format!("unknown vmware cursor type {other}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pixel_format::PixelFormat;

    #[test]
    fn cursor_with_alpha_unpremultiplies() {
        // Nested Raw + one opaque red pixel (already non-premult in this case)
        let mut data = vec![0u8, 0, 0, 0]; // Raw
        data.extend_from_slice(&[128, 0, 0, 128]); // half-alpha red premult
        let c = decode_cursor_with_alpha(1, 1, 0, 0, &data).unwrap();
        assert_eq!(c.rgba, vec![255, 0, 0, 128]);
    }

    #[test]
    fn xcursor_2x1() {
        // fg white, bg black; source bit0=1 bit1=0; mask both visible
        let mut data = vec![255, 255, 255, 0, 0, 0];
        data.push(0b1000_0000); // source row
        data.push(0b1100_0000); // mask row
        let c = decode_xcursor(2, 1, 1, 0, &data).unwrap();
        assert_eq!(c.width, 2);
        assert_eq!(&c.rgba[0..4], &[255, 255, 255, 255]);
        assert_eq!(&c.rgba[4..8], &[0, 0, 0, 255]);
        assert_eq!(c.hotspot_x, 1);
    }

    #[test]
    fn classic_cursor_mask() {
        let pf = PixelFormat::rgb888_le();
        // LE R at shift 0: [R,G,B,pad]
        let mut data = vec![255, 0, 0, 0];
        data.push(0b1000_0000); // visible
        let c = decode_cursor(&pf, 1, 1, 0, 0, &data).unwrap();
        assert_eq!(c.rgba[3], 255);
        assert_eq!(c.rgba[0], 255);
    }

    #[test]
    fn empty_cursor_with_alpha_still_has_nested_enc() {
        let c = decode_cursor_with_alpha(0, 0, 0, 0, &[0, 0, 0, 0]).unwrap();
        assert!(c.is_empty());
    }
}
