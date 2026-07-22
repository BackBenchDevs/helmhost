//! Tight (encoding 7) decoder → RGBA8.
//!
//! RFC Tight spec: comp_ctl byte upper nibble = subencoding type,
//! lower nibble = bitmask of which of the 4 zlib streams to reset.
//! Subencodings: 0x00-0x07 = basic compression (stream idx = bits 0-1),
//! 0x08 = Fill, 0x09 = JPEG.

use crate::io::read_exact;
use crate::pixel_format::{pixel_to_rgba, PixelFormat};
use flate2::{Decompress, FlushDecompress, Status};
use tokio::io::{AsyncRead, AsyncReadExt};

const TIGHT_MIN_TO_COMPRESS: usize = 12;

const TIGHT_FILL: u8 = 0x08;
const TIGHT_JPEG: u8 = 0x09;
const TIGHT_EXPLICIT_FILTER: u8 = 0x04;

const FILTER_COPY: u8 = 0;
const FILTER_PALETTE: u8 = 1;

/// Four per-connection zlib inflate streams (TigerVNC: streams 0-3).
pub struct TightStream {
    streams: [Decompress; 4],
}

impl TightStream {
    pub fn new() -> Self {
        Self {
            streams: core::array::from_fn(|_| Decompress::new(true)),
        }
    }
}

impl Default for TightStream {
    fn default() -> Self {
        Self::new()
    }
}

/// Decode compact 1-3 byte length. Returns `(length, bytes_consumed)`.
pub fn read_compact(buf: &[u8]) -> Result<(usize, usize), String> {
    if buf.is_empty() {
        return Err("tight compact: truncated".into());
    }
    let b0 = buf[0];
    if b0 & 0x80 == 0 {
        return Ok(((b0 & 0x7F) as usize, 1));
    }
    if buf.len() < 2 {
        return Err("tight compact: truncated (2)".into());
    }
    let b1 = buf[1];
    if b1 & 0x80 == 0 {
        return Ok((((b0 & 0x7F) as usize) | (((b1 & 0x7F) as usize) << 7), 2));
    }
    if buf.len() < 3 {
        return Err("tight compact: truncated (3)".into());
    }
    let b2 = buf[2];
    Ok((
        ((b0 & 0x7F) as usize) | (((b1 & 0x7F) as usize) << 7) | ((b2 as usize) << 14),
        3,
    ))
}

/// Decode a complete Tight rectangle body (starting with comp_ctl).
/// Returns RGBA8 pixels. Useful for unit tests / offline decode.
pub fn decode_tight_body(
    streams: &mut TightStream,
    pf: &PixelFormat,
    w: u32,
    h: u32,
    body: &[u8],
) -> Result<Vec<u8>, String> {
    if body.is_empty() {
        return Err("tight body empty".into());
    }
    let comp_ctl_raw = body[0];
    reset_streams(streams, comp_ctl_raw & 0x0F);
    let subenc = comp_ctl_raw >> 4;
    let pos = 1usize;

    match subenc {
        TIGHT_FILL => decode_fill(pf, w, h, body, pos),
        TIGHT_JPEG => {
            let (data_len, consumed) = read_compact(&body[pos..])?;
            let start = pos + consumed;
            if body.len() < start + data_len {
                return Err("tight jpeg truncated".into());
            }
            decode_jpeg(&body[start..start + data_len], w, h)
        }
        s if s <= 7 => {
            let stream_idx = (s & 0x03) as usize;
            let (filter_id, next) = if s & TIGHT_EXPLICIT_FILTER != 0 {
                if body.len() < pos + 1 {
                    return Err("tight filter id truncated".into());
                }
                (body[pos], pos + 1)
            } else {
                (FILTER_COPY, pos)
            };
            decode_basic_body(streams, stream_idx, pf, w, h, filter_id, &body[next..])
        }
        _ => Err(format!("tight: unsupported subencoding 0x{subenc:02x}")),
    }
}

/// Read and decode a Tight rectangle incrementally from an async stream.
/// Called from session reader after the 12-byte rect header is consumed.
pub async fn read_and_decode_tight<R>(
    rd: &mut R,
    streams: &mut TightStream,
    pf: &PixelFormat,
    w: u32,
    h: u32,
) -> Result<Vec<u8>, String>
where
    R: AsyncRead + Unpin,
{
    let comp_ctl_raw = read_u8(rd).await?;
    reset_streams(streams, comp_ctl_raw & 0x0F);
    let subenc = comp_ctl_raw >> 4;
    let is888 = is_888(pf);

    match subenc {
        TIGHT_FILL => {
            let nbytes = if is888 { 3 } else { pf.bytes_per_pixel() };
            let fill = read_exact(rd, nbytes).await?;
            let (r, g, b) = if is888 {
                (fill[0], fill[1], fill[2])
            } else {
                let rgba = pixel_to_rgba(pf, &fill);
                (rgba[0], rgba[1], rgba[2])
            };
            Ok(solid_rgba(w, h, r, g, b))
        }

        TIGHT_JPEG => {
            let data_len = read_compact_async(rd).await?;
            let jpeg_data = read_exact(rd, data_len).await?;
            decode_jpeg(&jpeg_data, w, h)
        }

        s if s <= 7 => {
            let stream_idx = (s & 0x03) as usize;
            let filter_id = if s & TIGHT_EXPLICIT_FILTER != 0 {
                read_u8(rd).await?
            } else {
                FILTER_COPY
            };
            decode_basic_async(rd, streams, stream_idx, pf, w, h, filter_id).await
        }

        _ => Err(format!("tight: unsupported subencoding 0x{subenc:02x}")),
    }
}

// --- helpers ---

fn is_888(pf: &PixelFormat) -> bool {
    pf.bits_per_pixel == 32 && pf.true_colour && pf.depth <= 24
}

fn reset_streams(streams: &mut TightStream, mask: u8) {
    for i in 0..4u8 {
        if mask & (1 << i) != 0 {
            streams.streams[i as usize] = Decompress::new(true);
        }
    }
}

fn solid_rgba(w: u32, h: u32, r: u8, g: u8, b: u8) -> Vec<u8> {
    let n = w as usize * h as usize;
    let mut out = Vec::with_capacity(n * 4);
    for _ in 0..n {
        out.extend_from_slice(&[r, g, b, 255]);
    }
    out
}

fn rgb24_to_rgba(pixels: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(pixels.len() / 3 * 4);
    for chunk in pixels.chunks_exact(3) {
        out.extend_from_slice(&[chunk[0], chunk[1], chunk[2], 255]);
    }
    out
}

fn bpp_to_rgba(pf: &PixelFormat, pixels: &[u8]) -> Vec<u8> {
    let bpp = pf.bytes_per_pixel();
    let mut out = Vec::with_capacity(pixels.len() / bpp * 4);
    for chunk in pixels.chunks_exact(bpp) {
        out.extend_from_slice(&pixel_to_rgba(pf, chunk));
    }
    out
}

fn inflate_stream(decompress: &mut Decompress, compressed: &[u8]) -> Result<Vec<u8>, String> {
    let mut out = Vec::with_capacity(compressed.len().saturating_mul(4).max(256));
    let mut remaining = compressed;

    while !remaining.is_empty() {
        if out.capacity().saturating_sub(out.len()) < 4096 {
            out.reserve(64 * 1024);
        }
        let before_in = decompress.total_in();
        let status = decompress
            .decompress_vec(remaining, &mut out, FlushDecompress::Sync)
            .map_err(|e| format!("tight inflate: {e}"))?;
        let consumed = (decompress.total_in() - before_in) as usize;
        if consumed == 0 {
            if matches!(status, Status::BufError) {
                out.reserve(64 * 1024);
                continue;
            }
            return Err("tight inflate: stalled".into());
        }
        remaining = &remaining[consumed..];
        if matches!(status, Status::StreamEnd) {
            break;
        }
    }
    loop {
        let before = out.len();
        if out.capacity().saturating_sub(out.len()) < 4096 {
            out.reserve(64 * 1024);
        }
        let status = decompress
            .decompress_vec(&[], &mut out, FlushDecompress::Sync)
            .map_err(|e| format!("tight inflate drain: {e}"))?;
        if out.len() == before || matches!(status, Status::StreamEnd) {
            break;
        }
    }
    Ok(out)
}

async fn read_u8<R: AsyncRead + Unpin>(rd: &mut R) -> Result<u8, String> {
    let mut buf = [0u8; 1];
    rd.read_exact(&mut buf)
        .await
        .map_err(|e| format!("tight read: {e}"))?;
    Ok(buf[0])
}

async fn read_compact_async<R: AsyncRead + Unpin>(rd: &mut R) -> Result<usize, String> {
    let b0 = read_u8(rd).await?;
    if b0 & 0x80 == 0 {
        return Ok((b0 & 0x7F) as usize);
    }
    let b1 = read_u8(rd).await?;
    if b1 & 0x80 == 0 {
        return Ok(((b0 & 0x7F) as usize) | (((b1 & 0x7F) as usize) << 7));
    }
    let b2 = read_u8(rd).await?;
    Ok(((b0 & 0x7F) as usize) | (((b1 & 0x7F) as usize) << 7) | ((b2 as usize) << 14))
}

async fn read_tight_pixels<R: AsyncRead + Unpin>(
    rd: &mut R,
    streams: &mut TightStream,
    stream_idx: usize,
    data_size: usize,
) -> Result<Vec<u8>, String> {
    if data_size < TIGHT_MIN_TO_COMPRESS {
        read_exact(rd, data_size).await
    } else {
        let zlen = read_compact_async(rd).await?;
        let zdata = read_exact(rd, zlen).await?;
        inflate_stream(&mut streams.streams[stream_idx], &zdata)
    }
}

// --- sync decode helpers (for decode_tight_body) ---

fn decode_fill(
    pf: &PixelFormat,
    w: u32,
    h: u32,
    body: &[u8],
    pos: usize,
) -> Result<Vec<u8>, String> {
    let (r, g, b) = if is_888(pf) {
        if body.len() < pos + 3 {
            return Err("tight fill truncated".into());
        }
        (body[pos], body[pos + 1], body[pos + 2])
    } else {
        let bpp = pf.bytes_per_pixel();
        if body.len() < pos + bpp {
            return Err("tight fill truncated".into());
        }
        let rgba = pixel_to_rgba(pf, &body[pos..pos + bpp]);
        (rgba[0], rgba[1], rgba[2])
    };
    Ok(solid_rgba(w, h, r, g, b))
}

/// `body_at_filter` is the slice starting right after comp_ctl (and optional filter byte).
fn decode_basic_body(
    streams: &mut TightStream,
    stream_idx: usize,
    pf: &PixelFormat,
    w: u32,
    h: u32,
    filter_id: u8,
    body_at_filter: &[u8],
) -> Result<Vec<u8>, String> {
    let is888 = is_888(pf);
    match filter_id {
        FILTER_COPY => {
            let bpp = if is888 { 3 } else { pf.bytes_per_pixel() };
            let data_size = w as usize * h as usize * bpp;
            let pixels = read_tight_pixels_sync(streams, stream_idx, body_at_filter, data_size)?;
            Ok(if is888 {
                rgb24_to_rgba(&pixels)
            } else {
                bpp_to_rgba(pf, &pixels)
            })
        }
        FILTER_PALETTE => {
            if body_at_filter.is_empty() {
                return Err("tight palette size truncated".into());
            }
            let palette_size = body_at_filter[0] as usize + 1;
            let bpc = if is888 { 3 } else { pf.bytes_per_pixel() };
            let pal_end = 1 + palette_size * bpc;
            if body_at_filter.len() < pal_end {
                return Err("tight palette data truncated".into());
            }
            let palette = build_palette(pf, is888, &body_at_filter[1..pal_end], palette_size, bpc);
            let row_size = if palette_size <= 2 {
                w.div_ceil(8) as usize
            } else {
                w as usize
            };
            let data_size = h as usize * row_size;
            let pixel_data =
                read_tight_pixels_sync(streams, stream_idx, &body_at_filter[pal_end..], data_size)?;
            unpack_palette(&palette, &pixel_data, w, h, palette_size)
        }
        _ => Err(format!("tight: unsupported filter 0x{filter_id:02x}")),
    }
}

/// Reads `data_size` uncompressed bytes or decompresses from zlib. `body` starts at the pixel data.
fn read_tight_pixels_sync(
    streams: &mut TightStream,
    stream_idx: usize,
    body: &[u8],
    data_size: usize,
) -> Result<Vec<u8>, String> {
    if data_size < TIGHT_MIN_TO_COMPRESS {
        if body.len() < data_size {
            return Err("tight pixels truncated".into());
        }
        Ok(body[..data_size].to_vec())
    } else {
        let (zlen, consumed) = read_compact(body)?;
        let zstart = consumed;
        if body.len() < zstart + zlen {
            return Err("tight zlib data truncated".into());
        }
        inflate_stream(
            &mut streams.streams[stream_idx],
            &body[zstart..zstart + zlen],
        )
    }
}

// --- async decode helpers ---

async fn decode_basic_async<R: AsyncRead + Unpin>(
    rd: &mut R,
    streams: &mut TightStream,
    stream_idx: usize,
    pf: &PixelFormat,
    w: u32,
    h: u32,
    filter_id: u8,
) -> Result<Vec<u8>, String> {
    let is888 = is_888(pf);
    match filter_id {
        FILTER_COPY => {
            let bpp = if is888 { 3 } else { pf.bytes_per_pixel() };
            let data_size = w as usize * h as usize * bpp;
            let pixels = read_tight_pixels(rd, streams, stream_idx, data_size).await?;
            Ok(if is888 {
                rgb24_to_rgba(&pixels)
            } else {
                bpp_to_rgba(pf, &pixels)
            })
        }
        FILTER_PALETTE => {
            let palette_size = read_u8(rd).await? as usize + 1;
            let bpc = if is888 { 3 } else { pf.bytes_per_pixel() };
            let pal_bytes = read_exact(rd, palette_size * bpc).await?;
            let palette = build_palette(pf, is888, &pal_bytes, palette_size, bpc);
            let row_size = if palette_size <= 2 {
                w.div_ceil(8) as usize
            } else {
                w as usize
            };
            let data_size = h as usize * row_size;
            let pixel_data = read_tight_pixels(rd, streams, stream_idx, data_size).await?;
            unpack_palette(&palette, &pixel_data, w, h, palette_size)
        }
        _ => Err(format!("tight: unsupported filter 0x{filter_id:02x}")),
    }
}

fn build_palette(
    pf: &PixelFormat,
    is888: bool,
    pal_bytes: &[u8],
    palette_size: usize,
    bpc: usize,
) -> Vec<[u8; 4]> {
    (0..palette_size)
        .map(|i| {
            let off = i * bpc;
            if is888 {
                [pal_bytes[off], pal_bytes[off + 1], pal_bytes[off + 2], 255]
            } else {
                pixel_to_rgba(pf, &pal_bytes[off..off + bpc])
            }
        })
        .collect()
}

fn unpack_palette(
    palette: &[[u8; 4]],
    pixel_data: &[u8],
    w: u32,
    h: u32,
    palette_size: usize,
) -> Result<Vec<u8>, String> {
    let total = w as usize * h as usize;
    let mut out = Vec::with_capacity(total * 4);

    if palette_size <= 2 {
        let row_size = w.div_ceil(8) as usize;
        for row in 0..h as usize {
            for x in 0..w as usize {
                let byte_idx = row * row_size + x / 8;
                let bit = 7 - (x % 8);
                if byte_idx >= pixel_data.len() {
                    return Err("tight palette row truncated".into());
                }
                let idx = ((pixel_data[byte_idx] >> bit) & 1) as usize;
                out.extend_from_slice(&palette[idx]);
            }
        }
    } else {
        for &idx_byte in pixel_data.iter().take(total) {
            let idx = idx_byte as usize;
            if idx >= palette.len() {
                return Err("tight palette index out of range".into());
            }
            out.extend_from_slice(&palette[idx]);
        }
    }
    Ok(out)
}

fn decode_jpeg(data: &[u8], _w: u32, _h: u32) -> Result<Vec<u8>, String> {
    use image::ImageReader;
    use std::io::Cursor;

    let img = ImageReader::new(Cursor::new(data))
        .with_guessed_format()
        .map_err(|e| format!("tight jpeg format: {e}"))?
        .decode()
        .map_err(|e| format!("tight jpeg decode: {e}"))?;

    Ok(img.to_rgba8().into_raw())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pixel_format::PixelFormat;

    fn pf() -> PixelFormat {
        PixelFormat::rgb888_le()
    }

    // comp_ctl = 0x80: upper nibble = TIGHT_FILL (8), lower nibble = 0 (no reset)
    #[test]
    fn fill_rect_solid_colour() {
        let mut streams = TightStream::new();
        let body = [0x80u8, 0xFF, 0x00, 0x80]; // fill + R=255, G=0, B=128
        let out = decode_tight_body(&mut streams, &pf(), 2, 2, &body).unwrap();
        assert_eq!(out.len(), 2 * 2 * 4);
        // Each pixel: [255, 0, 128, 255]
        for i in 0..4 {
            assert_eq!(&out[i * 4..(i + 1) * 4], &[255, 0, 128, 255]);
        }
    }

    #[test]
    fn fill_rect_resets_stream_on_mask() {
        let mut streams = TightStream::new();
        // comp_ctl = 0x81: upper nibble = TIGHT_FILL, lower nibble = 1 (reset stream 0)
        let body = [0x81u8, 0x10, 0x20, 0x30];
        let out = decode_tight_body(&mut streams, &pf(), 1, 1, &body).unwrap();
        assert_eq!(&out, &[0x10, 0x20, 0x30, 255]);
    }

    #[test]
    fn compact_length_one_byte() {
        let buf = [0x7Fu8]; // 127
        let (len, consumed) = read_compact(&buf).unwrap();
        assert_eq!(len, 127);
        assert_eq!(consumed, 1);
    }

    #[test]
    fn compact_length_two_bytes() {
        // 0x80 | 0x01 = first byte (0x81 has bit7 set, low 7 bits = 1)
        // second byte = 0x03 (bit7 clear, low 7 bits = 3)
        // length = 1 | (3 << 7) = 1 + 384 = 385
        let buf = [0x81u8, 0x03];
        let (len, consumed) = read_compact(&buf).unwrap();
        assert_eq!(len, 1 | (3 << 7));
        assert_eq!(consumed, 2);
    }

    #[test]
    fn compact_length_three_bytes() {
        // b0 = 0x81 (low7 = 1, continues)
        // b1 = 0x81 (low7 = 1, continues)
        // b2 = 0x02 (all 8 bits)
        // length = 1 | (1 << 7) | (2 << 14) = 1 + 128 + 32768 = 32897
        let buf = [0x81u8, 0x81, 0x02];
        let (len, consumed) = read_compact(&buf).unwrap();
        assert_eq!(len, 1 | (1 << 7) | (2 << 14));
        assert_eq!(consumed, 3);
    }

    #[test]
    fn compact_empty_is_error() {
        assert!(read_compact(&[]).is_err());
    }

    #[test]
    fn basic_copy_raw_small_rect() {
        // subencoding 0x00 = basic, stream 0, no explicit filter (copy)
        // 1x1 pixel, 3 bytes < TIGHT_MIN_TO_COMPRESS=12, so raw
        let mut streams = TightStream::new();
        // comp_ctl = 0x00: basic stream 0, copy filter assumed
        let body = [0x00u8, 0xAA, 0xBB, 0xCC]; // comp_ctl + 3 RGB bytes
        let out = decode_tight_body(&mut streams, &pf(), 1, 1, &body).unwrap();
        assert_eq!(&out, &[0xAA, 0xBB, 0xCC, 0xFF]);
    }
}
