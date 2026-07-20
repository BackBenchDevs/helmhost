//! ZRLE (encoding 16) decoder → RGBA8.
//!
//! RFC 6143: one zlib inflate stream per RFB connection — rectangles must be
//! decoded in order with shared zlib state (Sync-flushed between rects).
//! Some servers reset zlib per rectangle; dual-mode falls back to that.

use crate::pixel_format::{pixel_to_rgba, PixelFormat};
use flate2::{Compress, Compression, Decompress, FlushCompress, FlushDecompress, Status};

const TILE: u32 = 64;

/// Connection-scoped ZRLE zlib inflater (TigerVNC-style).
pub struct ZrleStream {
    decompress: Decompress,
    /// When true, reset zlib before every rectangle (non-RFC servers).
    per_rect: bool,
}

impl Default for ZrleStream {
    fn default() -> Self {
        Self::new()
    }
}

impl ZrleStream {
    pub fn new() -> Self {
        Self {
            decompress: Decompress::new(true),
            per_rect: false,
        }
    }

    pub fn is_per_rect(&self) -> bool {
        self.per_rect
    }

    /// Inflate one ZRLE rectangle's zlib payload (Sync flush).
    /// Consumes all `compressed` bytes (like TigerVNC `flushUnderlying`).
    pub fn inflate(&mut self, compressed: &[u8]) -> Result<Vec<u8>, String> {
        if self.per_rect {
            self.decompress = Decompress::new(true);
        }
        match self.inflate_once(compressed) {
            Ok(out) => Ok(out),
            Err(first) if !self.per_rect => {
                self.decompress = Decompress::new(true);
                match self.inflate_once(compressed) {
                    Ok(out) => {
                        self.per_rect = true;
                        Ok(out)
                    }
                    Err(second) => Err(format!("{first}; reset retry: {second}")),
                }
            }
            Err(e) => Err(e),
        }
    }

    fn inflate_once(&mut self, compressed: &[u8]) -> Result<Vec<u8>, String> {
        let mut out = Vec::with_capacity(compressed.len().saturating_mul(4).max(256));
        let mut remaining = compressed;

        while !remaining.is_empty() {
            let before_in = self.decompress.total_in();
            let before_len = out.len();
            if out.capacity() - out.len() < 4096 {
                out.reserve(64 * 1024);
            }
            let status = self
                .decompress
                .decompress_vec(remaining, &mut out, FlushDecompress::Sync)
                .map_err(|e| format!("zrle inflate: {e}"))?;
            let consumed = (self.decompress.total_in() - before_in) as usize;

            if consumed == 0 && out.len() == before_len {
                if matches!(status, Status::BufError) {
                    out.reserve(64 * 1024);
                    continue;
                }
                return Err("zrle inflate: stalled with input remaining".into());
            }
            remaining = &remaining[consumed..];
            if matches!(status, Status::StreamEnd) {
                if !remaining.is_empty() {
                    return Err("zrle inflate: stream ended with input left".into());
                }
                break;
            }
        }

        // Drain Sync-flushed output with no further input.
        loop {
            let before_len = out.len();
            if out.capacity() - out.len() < 4096 {
                out.reserve(64 * 1024);
            }
            let status = self
                .decompress
                .decompress_vec(&[], &mut out, FlushDecompress::Sync)
                .map_err(|e| format!("zrle inflate: {e}"))?;
            if out.len() == before_len || matches!(status, Status::StreamEnd) {
                break;
            }
        }
        Ok(out)
    }
}

/// Decode one ZRLE rectangle (fresh zlib stream — for single-rect fixtures/tests).
pub fn decode_zrle(
    pf: &PixelFormat,
    width: u32,
    height: u32,
    data: &[u8],
) -> Result<Vec<u8>, String> {
    let mut stream = ZrleStream::new();
    decode_zrle_with(&mut stream, pf, width, height, data)
}

/// Decode one ZRLE rectangle using a connection-scoped zlib stream.
pub fn decode_zrle_with(
    stream: &mut ZrleStream,
    pf: &PixelFormat,
    width: u32,
    height: u32,
    data: &[u8],
) -> Result<Vec<u8>, String> {
    if data.len() < 4 {
        return Err("zrle length truncated".into());
    }
    let zlen = u32::from_be_bytes([data[0], data[1], data[2], data[3]]) as usize;
    if data.len() < 4 + zlen {
        return Err("zrle payload truncated".into());
    }
    let inflated = stream.inflate(&data[4..4 + zlen])?;
    decode_tiles(pf, width, height, &inflated)
}

fn decode_tiles(
    pf: &PixelFormat,
    width: u32,
    height: u32,
    inflated: &[u8],
) -> Result<Vec<u8>, String> {
    let bpp = pf.bytes_per_pixel();
    // ZRLE uses CPIXEL: for 32bpp true-colour, 3 bytes RGB (omit unused).
    let cpixel = if pf.bits_per_pixel == 32 && pf.true_colour && pf.depth <= 24 {
        3
    } else {
        bpp
    };

    let mut out = vec![0u8; width as usize * height as usize * 4];
    let mut cursor = 0usize;

    let mut ty = 0u32;
    while ty < height {
        let th = (height - ty).min(TILE);
        let mut tx = 0u32;
        while tx < width {
            let tw = (width - tx).min(TILE);
            cursor = decode_tile(
                pf,
                cpixel,
                inflated,
                cursor,
                &mut out,
                TileGeom {
                    fb_w: width,
                    tx,
                    ty,
                    tw,
                    th,
                },
            )?;
            tx += tw;
        }
        ty += th;
    }
    Ok(out)
}

fn read_cpixel(pf: &PixelFormat, cpixel: usize, data: &[u8], off: usize) -> Result<[u8; 4], String> {
    if data.len() < off + cpixel {
        return Err("zrle cpixel truncated".into());
    }
    if cpixel == 3 {
        let mut pix = [0u8; 4];
        pix[0] = data[off];
        pix[1] = data[off + 1];
        pix[2] = data[off + 2];
        Ok(pixel_to_rgba(pf, &pix))
    } else {
        Ok(pixel_to_rgba(pf, &data[off..off + cpixel]))
    }
}

fn put_pixel(out: &mut [u8], fb_w: u32, x: u32, y: u32, rgba: [u8; 4]) {
    let off = (y as usize * fb_w as usize + x as usize) * 4;
    out[off..off + 4].copy_from_slice(&rgba);
}

struct TileGeom {
    fb_w: u32,
    tx: u32,
    ty: u32,
    tw: u32,
    th: u32,
}

fn decode_tile(
    pf: &PixelFormat,
    cpixel: usize,
    data: &[u8],
    mut cursor: usize,
    out: &mut [u8],
    geom: TileGeom,
) -> Result<usize, String> {
    let TileGeom {
        fb_w,
        tx,
        ty,
        tw,
        th,
    } = geom;
    if cursor >= data.len() {
        return Err("zrle tile truncated".into());
    }
    let sub = data[cursor];
    cursor += 1;

    if sub == 0 {
        for y in 0..th {
            for x in 0..tw {
                let rgba = read_cpixel(pf, cpixel, data, cursor)?;
                cursor += cpixel;
                put_pixel(out, fb_w, tx + x, ty + y, rgba);
            }
        }
        return Ok(cursor);
    }

    if sub == 1 {
        let rgba = read_cpixel(pf, cpixel, data, cursor)?;
        cursor += cpixel;
        for y in 0..th {
            for x in 0..tw {
                put_pixel(out, fb_w, tx + x, ty + y, rgba);
            }
        }
        return Ok(cursor);
    }

    if (2..=16).contains(&sub) {
        let palette_size = sub as usize;
        let mut palette = Vec::with_capacity(palette_size);
        for _ in 0..palette_size {
            palette.push(read_cpixel(pf, cpixel, data, cursor)?);
            cursor += cpixel;
        }
        let bits = if palette_size <= 2 {
            1
        } else if palette_size <= 4 {
            2
        } else {
            4
        };
        for y in 0..th {
            let mut packed: u8 = 0;
            let mut bits_left = 0u8;
            for x in 0..tw {
                if bits_left == 0 {
                    if cursor >= data.len() {
                        return Err("zrle packed truncated".into());
                    }
                    packed = data[cursor];
                    cursor += 1;
                    bits_left = 8;
                }
                bits_left -= bits;
                let idx = (packed >> bits_left) & ((1 << bits) - 1);
                let rgba = palette
                    .get(idx as usize)
                    .copied()
                    .ok_or_else(|| "zrle palette index".to_string())?;
                put_pixel(out, fb_w, tx + x, ty + y, rgba);
            }
        }
        return Ok(cursor);
    }

    if sub == 128 {
        let mut n = 0u32;
        let total = tw * th;
        while n < total {
            let rgba = read_cpixel(pf, cpixel, data, cursor)?;
            cursor += cpixel;
            let (run, c2) = read_rle_length(data, cursor)?;
            cursor = c2;
            for _ in 0..run {
                let px = n % tw;
                let py = n / tw;
                put_pixel(out, fb_w, tx + px, ty + py, rgba);
                n += 1;
                if n > total {
                    return Err("zrle rle overrun".into());
                }
            }
        }
        return Ok(cursor);
    }

    if sub >= 130 {
        let palette_size = (sub - 128) as usize;
        let mut palette = Vec::with_capacity(palette_size);
        for _ in 0..palette_size {
            palette.push(read_cpixel(pf, cpixel, data, cursor)?);
            cursor += cpixel;
        }
        let mut n = 0u32;
        let total = tw * th;
        while n < total {
            if cursor >= data.len() {
                return Err("zrle palette-rle truncated".into());
            }
            let b = data[cursor];
            cursor += 1;
            if b & 0x80 == 0 {
                let idx = b as usize;
                let rgba = *palette.get(idx).ok_or_else(|| "zrle pal idx".to_string())?;
                let px = n % tw;
                let py = n / tw;
                put_pixel(out, fb_w, tx + px, ty + py, rgba);
                n += 1;
            } else {
                let idx = (b & 0x7f) as usize;
                let rgba = *palette.get(idx).ok_or_else(|| "zrle pal idx".to_string())?;
                let (run, c2) = read_rle_length(data, cursor)?;
                cursor = c2;
                for _ in 0..run {
                    let px = n % tw;
                    let py = n / tw;
                    put_pixel(out, fb_w, tx + px, ty + py, rgba);
                    n += 1;
                    if n > total {
                        return Err("zrle pal-rle overrun".into());
                    }
                }
            }
        }
        return Ok(cursor);
    }

    Err(format!("unsupported zrle subencoding {sub}"))
}

fn read_rle_length(data: &[u8], mut cursor: usize) -> Result<(u32, usize), String> {
    let mut len = 1u32;
    loop {
        if cursor >= data.len() {
            return Err("zrle rle length truncated".into());
        }
        let b = data[cursor];
        cursor += 1;
        len += u32::from(b);
        if b != 255 {
            return Ok((len, cursor));
        }
    }
}

fn compress_sync(compressor: &mut Compress, raw: &[u8]) -> Vec<u8> {
    let mut z = Vec::new();
    let mut input = raw;
    while !input.is_empty() {
        let before = compressor.total_in();
        compressor
            .compress_vec(input, &mut z, FlushCompress::Sync)
            .expect("zrle compress");
        let consumed = (compressor.total_in() - before) as usize;
        if consumed == 0 {
            z.reserve(1024);
            continue;
        }
        input = &input[consumed..];
    }
    loop {
        let before = z.len();
        compressor
            .compress_vec(&[], &mut z, FlushCompress::Sync)
            .expect("zrle compress flush");
        if z.len() == before {
            break;
        }
    }
    z
}

fn solid_tile_bytes(w: u32, h: u32, rgb: [u8; 3]) -> Vec<u8> {
    let mut raw = Vec::new();
    let mut ty = 0u32;
    while ty < h {
        let mut tx = 0u32;
        while tx < w {
            raw.push(1);
            raw.extend_from_slice(&rgb);
            tx += (w - tx).min(TILE);
        }
        ty += (h - ty).min(TILE);
    }
    raw
}

/// Build a minimal zlib-framed ZRLE solid-colour rectangle (for fixtures).
pub fn encode_zrle_solid_fixture(pf: &PixelFormat, w: u32, h: u32, rgb: [u8; 3]) -> Vec<u8> {
    let _ = pf;
    let mut compressor = Compress::new(Compression::default(), true);
    encode_zrle_solid_with(&mut compressor, w, h, rgb)
}

/// Encode a solid ZRLE rect with a persistent compressor (multi-rect tests).
pub fn encode_zrle_solid_with(
    compressor: &mut Compress,
    w: u32,
    h: u32,
    rgb: [u8; 3],
) -> Vec<u8> {
    let raw = solid_tile_bytes(w, h, rgb);
    let z = compress_sync(compressor, &raw);
    let mut out = Vec::with_capacity(4 + z.len());
    out.extend_from_slice(&(z.len() as u32).to_be_bytes());
    out.extend_from_slice(&z);
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pixel_format::PixelFormat;

    #[test]
    fn persistent_zlib_two_rects() {
        let pf = PixelFormat::rgb888_le();
        let mut compressor = Compress::new(Compression::default(), true);
        let r1 = encode_zrle_solid_with(&mut compressor, 2, 2, [10, 20, 30]);
        let r2 = encode_zrle_solid_with(&mut compressor, 2, 2, [40, 50, 60]);

        assert!(decode_zrle(&pf, 2, 2, &r1).is_ok());
        assert!(
            decode_zrle(&pf, 2, 2, &r2).is_err(),
            "second rect must fail without shared stream"
        );

        let mut stream = ZrleStream::new();
        let a = decode_zrle_with(&mut stream, &pf, 2, 2, &r1).unwrap();
        let b = decode_zrle_with(&mut stream, &pf, 2, 2, &r2).unwrap();
        assert!(!stream.is_per_rect());
        assert_eq!(&a[0..3], &[10, 20, 30]);
        assert_eq!(&b[0..3], &[40, 50, 60]);
    }

    #[test]
    fn independent_zlib_per_rect_dual_mode() {
        let pf = PixelFormat::rgb888_le();
        // Each rect is a complete standalone zlib stream (non-RFC).
        let r1 = {
            let mut c = Compress::new(Compression::default(), true);
            encode_zrle_solid_with(&mut c, 2, 2, [10, 20, 30])
        };
        let r2 = {
            let mut c = Compress::new(Compression::default(), true);
            encode_zrle_solid_with(&mut c, 2, 2, [40, 50, 60])
        };

        let mut stream = ZrleStream::new();
        let a = decode_zrle_with(&mut stream, &pf, 2, 2, &r1).unwrap();
        // Second independent stream would corrupt a persistent inflater;
        // dual-mode must reset and switch to per-rect.
        let b = decode_zrle_with(&mut stream, &pf, 2, 2, &r2).unwrap();
        assert!(stream.is_per_rect());
        assert_eq!(&a[0..3], &[10, 20, 30]);
        assert_eq!(&b[0..3], &[40, 50, 60]);
    }
}
