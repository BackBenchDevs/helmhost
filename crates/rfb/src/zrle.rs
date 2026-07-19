//! ZRLE (encoding 16) decoder → RGBA8.

use crate::pixel_format::{pixel_to_rgba, PixelFormat};
use flate2::read::ZlibDecoder;
use std::io::Read;

pub const ENC_ZRLE: i32 = 16;
const TILE: u32 = 64;

/// Decode one ZRLE rectangle into tightly packed RGBA8.
pub fn decode_zrle(
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
    let mut decoder = ZlibDecoder::new(&data[4..4 + zlen]);
    let mut inflated = Vec::new();
    decoder
        .read_to_end(&mut inflated)
        .map_err(|e| format!("zrle inflate: {e}"))?;

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
                &inflated,
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
        // Assume LE RGB packed into 32bpp pixel layout
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
        // Raw
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
        // Solid
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
        // Plain RLE
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
        // Palette RLE
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

/// Build a minimal zlib-framed ZRLE solid-colour rectangle (for fixtures).
pub fn encode_zrle_solid_fixture(pf: &PixelFormat, w: u32, h: u32, rgb: [u8; 3]) -> Vec<u8> {
    use flate2::write::ZlibEncoder;
    use flate2::Compression;
    use std::io::Write;

    let cpixel = 3;
    let mut raw = Vec::new();
    let mut ty = 0u32;
    while ty < h {
        let th = (h - ty).min(TILE);
        let mut tx = 0u32;
        while tx < w {
            let _tw = (w - tx).min(TILE);
            raw.push(1); // solid
            raw.extend_from_slice(&rgb[..cpixel]);
            // map to pf shifts when writing cpixel as R,G,B in LE order matching rgb888_le
            let _ = pf;
            tx += (w - tx).min(TILE);
        }
        ty += th;
    }

    let mut enc = ZlibEncoder::new(Vec::new(), Compression::default());
    enc.write_all(&raw).unwrap();
    let z = enc.finish().unwrap();
    let mut out = Vec::with_capacity(4 + z.len());
    out.extend_from_slice(&(z.len() as u32).to_be_bytes());
    out.extend_from_slice(&z);
    out
}
