//! Convert pixels using RFB pixel format.

/// RFB PIXEL_FORMAT (16 bytes).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PixelFormat {
    pub bits_per_pixel: u8,
    pub depth: u8,
    pub big_endian: bool,
    pub true_colour: bool,
    pub red_max: u16,
    pub green_max: u16,
    pub blue_max: u16,
    pub red_shift: u8,
    pub green_shift: u8,
    pub blue_shift: u8,
}

impl PixelFormat {
    /// Common 32bpp little-endian (R at shift 0).
    pub fn rgb888_le() -> Self {
        Self {
            bits_per_pixel: 32,
            depth: 24,
            big_endian: false,
            true_colour: true,
            red_max: 255,
            green_max: 255,
            blue_max: 255,
            red_shift: 0,
            green_shift: 8,
            blue_shift: 16,
        }
    }

    pub fn encode(&self) -> [u8; 16] {
        let mut b = [0u8; 16];
        b[0] = self.bits_per_pixel;
        b[1] = self.depth;
        b[2] = u8::from(self.big_endian);
        b[3] = u8::from(self.true_colour);
        b[4..6].copy_from_slice(&self.red_max.to_be_bytes());
        b[6..8].copy_from_slice(&self.green_max.to_be_bytes());
        b[8..10].copy_from_slice(&self.blue_max.to_be_bytes());
        b[10] = self.red_shift;
        b[11] = self.green_shift;
        b[12] = self.blue_shift;
        b
    }

    pub fn decode(b: &[u8]) -> Result<Self, String> {
        if b.len() < 16 {
            return Err("pixel format truncated".into());
        }
        Ok(Self {
            bits_per_pixel: b[0],
            depth: b[1],
            big_endian: b[2] != 0,
            true_colour: b[3] != 0,
            red_max: u16::from_be_bytes([b[4], b[5]]),
            green_max: u16::from_be_bytes([b[6], b[7]]),
            blue_max: u16::from_be_bytes([b[8], b[9]]),
            red_shift: b[10],
            green_shift: b[11],
            blue_shift: b[12],
        })
    }

    pub fn bytes_per_pixel(&self) -> usize {
        (self.bits_per_pixel as usize).div_ceil(8)
    }
}

fn read_pixel_value(pf: &PixelFormat, pix: &[u8]) -> u32 {
    let bpp = pf.bytes_per_pixel();
    let mut v = 0u32;
    if pf.big_endian {
        for i in 0..bpp {
            v = (v << 8) | u32::from(pix.get(i).copied().unwrap_or(0));
        }
    } else {
        for i in 0..bpp {
            v |= u32::from(pix.get(i).copied().unwrap_or(0)) << (8 * i);
        }
    }
    v
}

/// Convert one Raw pixel to RGBA8.
pub fn pixel_to_rgba(pf: &PixelFormat, pix: &[u8]) -> [u8; 4] {
    let v = read_pixel_value(pf, pix);
    let r = ((v >> pf.red_shift) & u32::from(pf.red_max)) as u8;
    let g = ((v >> pf.green_shift) & u32::from(pf.green_max)) as u8;
    let b = ((v >> pf.blue_shift) & u32::from(pf.blue_max)) as u8;
    [r, g, b, 255]
}

/// Expand Raw rectangle bytes to RGBA8 tightly packed.
pub fn raw_to_rgba(
    pf: &PixelFormat,
    width: u32,
    height: u32,
    data: &[u8],
) -> Result<Vec<u8>, String> {
    let bpp = pf.bytes_per_pixel();
    let expected = bpp * width as usize * height as usize;
    if data.len() < expected {
        return Err(format!("raw data short: {} < {}", data.len(), expected));
    }
    let mut out = Vec::with_capacity(width as usize * height as usize * 4);
    for pix in data[..expected].chunks_exact(bpp) {
        out.extend_from_slice(&pixel_to_rgba(pf, pix));
    }
    Ok(out)
}
