//! RGBA8 framebuffer cache (protocol-agnostic).

use crate::protocol::Rect;

/// Tightly packed RGBA8 framebuffer.
#[derive(Debug, Clone)]
pub struct FramebufferCache {
    width: u32,
    height: u32,
    pixels: Vec<u8>,
}

impl FramebufferCache {
    pub fn new(width: u32, height: u32) -> Self {
        let n = width as usize * height as usize * 4;
        Self {
            width,
            height,
            pixels: vec![0u8; n],
        }
    }

    pub fn resize(&mut self, width: u32, height: u32) {
        *self = Self::new(width, height);
    }

    pub fn size(&self) -> (u32, u32) {
        (self.width, self.height)
    }

    pub fn byte_len(&self) -> usize {
        self.width as usize * self.height as usize * 4
    }

    pub fn copy_to(&self, out: &mut [u8]) -> Result<(), String> {
        let n = self.byte_len();
        if out.len() < n {
            return Err(format!("fb buffer short: need {n}, got {}", out.len()));
        }
        out[..n].copy_from_slice(&self.pixels);
        Ok(())
    }

    /// Copy one axis-aligned rect into a tightly packed RGBA8 buffer (`w*h*4`).
    pub fn copy_rect_to(&self, rect: Rect, out: &mut [u8]) -> Result<(), String> {
        if rect.x < 0 || rect.y < 0 {
            return Err("copy_rect_to: negative origin".into());
        }
        let x = rect.x as u32;
        let y = rect.y as u32;
        if x + rect.w > self.width || y + rect.h > self.height {
            return Err("copy_rect_to: out of bounds".into());
        }
        let need = rect.w as usize * rect.h as usize * 4;
        if out.len() < need {
            return Err(format!(
                "copy_rect_to: buffer short need {need} got {}",
                out.len()
            ));
        }
        for row in 0..rect.h {
            let src_off =
                ((y + row) as usize * self.width as usize + x as usize) * 4;
            let dst_off = row as usize * rect.w as usize * 4;
            let len = rect.w as usize * 4;
            out[dst_off..dst_off + len]
                .copy_from_slice(&self.pixels[src_off..src_off + len]);
        }
        Ok(())
    }

    pub fn put_damage(&mut self, rect: Rect, rgba: &[u8]) -> Result<(), String> {
        let expected = rect.w as usize * rect.h as usize * 4;
        if rgba.len() < expected {
            return Err("damage rgba short".into());
        }
        for row in 0..rect.h {
            let src_off = row as usize * rect.w as usize * 4;
            let dst_x = rect.x as u32;
            let dst_y = rect.y as u32 + row;
            if dst_x + rect.w > self.width || dst_y >= self.height {
                return Err("damage out of bounds".into());
            }
            let dst_off = (dst_y as usize * self.width as usize + dst_x as usize) * 4;
            let len = rect.w as usize * 4;
            self.pixels[dst_off..dst_off + len].copy_from_slice(&rgba[src_off..src_off + len]);
        }
        Ok(())
    }

    /// Copy source rect into destination (CopyRect semantics).
    pub fn copy_rect(&mut self, dst: Rect, src_x: i32, src_y: i32) -> Result<(), String> {
        if dst.x < 0 || dst.y < 0 || src_x < 0 || src_y < 0 {
            return Err("copyrect negative".into());
        }
        let sw = dst.w;
        let sh = dst.h;
        if src_x as u32 + sw > self.width
            || src_y as u32 + sh > self.height
            || dst.x as u32 + sw > self.width
            || dst.y as u32 + sh > self.height
        {
            return Err("copyrect out of bounds".into());
        }
        let mut rgba = vec![0u8; sw as usize * sh as usize * 4];
        for row in 0..sh {
            let src_off =
                ((src_y as u32 + row) as usize * self.width as usize + src_x as usize) * 4;
            let len = sw as usize * 4;
            let dst_off = row as usize * sw as usize * 4;
            rgba[dst_off..dst_off + len].copy_from_slice(&self.pixels[src_off..src_off + len]);
        }
        self.put_damage(dst, &rgba)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn copy_rect_to_happy_path() {
        let mut fb = FramebufferCache::new(4, 3);
        // Fill with recognizable pattern: pixel (x,y) = [x,y,0,255]
        for y in 0..3u32 {
            for x in 0..4u32 {
                let off = (y as usize * 4 + x as usize) * 4;
                fb.pixels[off] = x as u8;
                fb.pixels[off + 1] = y as u8;
                fb.pixels[off + 2] = 0;
                fb.pixels[off + 3] = 255;
            }
        }
        let mut out = vec![0u8; 2 * 2 * 4];
        fb.copy_rect_to(
            Rect {
                x: 1,
                y: 1,
                w: 2,
                h: 2,
            },
            &mut out,
        )
        .unwrap();
        assert_eq!(&out[0..4], &[1, 1, 0, 255]);
        assert_eq!(&out[4..8], &[2, 1, 0, 255]);
        assert_eq!(&out[8..12], &[1, 2, 0, 255]);
        assert_eq!(&out[12..16], &[2, 2, 0, 255]);
    }

    #[test]
    fn copy_rect_to_oob_rejects() {
        let fb = FramebufferCache::new(10, 10);
        let mut out = vec![0u8; 4];
        assert!(fb
            .copy_rect_to(
                Rect {
                    x: 9,
                    y: 0,
                    w: 2,
                    h: 1,
                },
                &mut out,
            )
            .is_err());
    }
}
