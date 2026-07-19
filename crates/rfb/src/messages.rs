//! Client → server and server → client message codecs.

use crate::pixel_format::{raw_to_rgba, PixelFormat};
use helmhost_core::{KeyEvent, PointerEvent, Rect};

pub const MSG_FRAMEBUFFER_UPDATE: u8 = 0;
pub const MSG_SET_COLOUR_MAP: u8 = 1;
pub const MSG_BELL: u8 = 2;
pub const MSG_SERVER_CUT_TEXT: u8 = 3;

pub const ENC_RAW: i32 = 0;
pub const ENC_COPYRECT: i32 = 1;
pub const ENC_ZRLE: i32 = 16;
pub const ENC_DESKTOP_SIZE: i32 = -223;
pub const ENC_LAST_RECT: i32 = -224;

pub const CLIENT_SET_PIXEL_FORMAT: u8 = 0;
pub const CLIENT_SET_ENCODINGS: u8 = 2;
pub const CLIENT_FB_UPDATE_REQUEST: u8 = 3;
pub const CLIENT_KEY_EVENT: u8 = 4;
pub const CLIENT_POINTER_EVENT: u8 = 5;
pub const CLIENT_CUT_TEXT: u8 = 6;

pub fn encode_set_encodings(encodings: &[i32]) -> Vec<u8> {
    let mut out = Vec::with_capacity(4 + encodings.len() * 4);
    out.push(CLIENT_SET_ENCODINGS);
    out.push(0);
    out.extend_from_slice(&(encodings.len() as u16).to_be_bytes());
    for e in encodings {
        out.extend_from_slice(&e.to_be_bytes());
    }
    out
}

pub fn preferred_encodings() -> [i32; 3] {
    [ENC_ZRLE, ENC_COPYRECT, ENC_RAW]
}

pub fn encode_fb_update_request(incremental: bool, x: u16, y: u16, w: u16, h: u16) -> [u8; 10] {
    let mut b = [0u8; 10];
    b[0] = CLIENT_FB_UPDATE_REQUEST;
    b[1] = u8::from(incremental);
    b[2..4].copy_from_slice(&x.to_be_bytes());
    b[4..6].copy_from_slice(&y.to_be_bytes());
    b[6..8].copy_from_slice(&w.to_be_bytes());
    b[8..10].copy_from_slice(&h.to_be_bytes());
    b
}

pub fn encode_pointer_event(ev: PointerEvent) -> [u8; 6] {
    let mut b = [0u8; 6];
    b[0] = CLIENT_POINTER_EVENT;
    b[1] = ev.buttons;
    b[2..4].copy_from_slice(&(ev.x as u16).to_be_bytes());
    b[4..6].copy_from_slice(&(ev.y as u16).to_be_bytes());
    b
}

pub fn encode_key_event(ev: KeyEvent) -> [u8; 8] {
    let mut b = [0u8; 8];
    b[0] = CLIENT_KEY_EVENT;
    b[1] = u8::from(ev.down);
    b[2] = 0;
    b[3] = 0;
    b[4..8].copy_from_slice(&ev.keysym.to_be_bytes());
    b
}

pub fn encode_set_pixel_format(pf: &PixelFormat) -> [u8; 20] {
    let mut b = [0u8; 20];
    b[0] = CLIENT_SET_PIXEL_FORMAT;
    b[4..20].copy_from_slice(&pf.encode());
    b
}

pub fn encode_client_cut_text(text: &str) -> Vec<u8> {
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(8 + bytes.len());
    out.push(CLIENT_CUT_TEXT);
    out.extend_from_slice(&[0, 0, 0]);
    out.extend_from_slice(&(bytes.len() as u32).to_be_bytes());
    out.extend_from_slice(bytes);
    out
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FramebufferRectHeader {
    pub x: u16,
    pub y: u16,
    pub w: u16,
    pub h: u16,
    pub encoding: i32,
}

pub fn parse_fb_update_header(buf: &[u8]) -> Result<(u16, usize), String> {
    if buf.len() < 4 {
        return Err("fb update header truncated".into());
    }
    if buf[0] != MSG_FRAMEBUFFER_UPDATE {
        return Err(format!("expected FramebufferUpdate, got {}", buf[0]));
    }
    let n = u16::from_be_bytes([buf[2], buf[3]]);
    Ok((n, 4))
}

pub fn parse_rect_header(buf: &[u8]) -> Result<(FramebufferRectHeader, usize), String> {
    if buf.len() < 12 {
        return Err("rect header truncated".into());
    }
    Ok((
        FramebufferRectHeader {
            x: u16::from_be_bytes([buf[0], buf[1]]),
            y: u16::from_be_bytes([buf[2], buf[3]]),
            w: u16::from_be_bytes([buf[4], buf[5]]),
            h: u16::from_be_bytes([buf[6], buf[7]]),
            encoding: i32::from_be_bytes([buf[8], buf[9], buf[10], buf[11]]),
        },
        12,
    ))
}

/// Decode one Raw rectangle to RGBA8.
pub fn decode_raw_rect(
    pf: &PixelFormat,
    hdr: &FramebufferRectHeader,
    data: &[u8],
) -> Result<(Rect, Vec<u8>), String> {
    if hdr.encoding != ENC_RAW {
        return Err(format!("unsupported encoding {}", hdr.encoding));
    }
    let bpp = pf.bytes_per_pixel();
    let nbytes = bpp * hdr.w as usize * hdr.h as usize;
    if data.len() < nbytes {
        return Err("raw rect truncated".into());
    }
    let rgba = raw_to_rgba(pf, u32::from(hdr.w), u32::from(hdr.h), &data[..nbytes])?;
    Ok((
        Rect {
            x: i32::from(hdr.x),
            y: i32::from(hdr.y),
            w: u32::from(hdr.w),
            h: u32::from(hdr.h),
        },
        rgba,
    ))
}

/// Legacy name used by older unit tests.
pub fn apply_raw_rect(
    pf: &PixelFormat,
    hdr: &FramebufferRectHeader,
    data: &[u8],
) -> Result<(Rect, Vec<u8>), String> {
    decode_raw_rect(pf, hdr, data)
}

pub fn parse_copyrect_src(data: &[u8]) -> Result<(u16, u16), String> {
    if data.len() < 4 {
        return Err("copyrect truncated".into());
    }
    Ok((
        u16::from_be_bytes([data[0], data[1]]),
        u16::from_be_bytes([data[2], data[3]]),
    ))
}

pub fn parse_server_cut_text(payload: &[u8]) -> Result<String, String> {
    String::from_utf8(payload.to_vec()).map_err(|e| e.to_string())
}
