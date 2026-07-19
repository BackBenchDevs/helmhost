//! Raw framebuffer → FrameSink (B2) and input encode (B3).

use helmhost_core::{FrameSink, KeyEvent, PointerEvent, Rect};
use helmhost_rfb::messages::{
    apply_raw_rect, encode_fb_update_request, encode_key_event, encode_pointer_event,
    parse_fb_update_header, parse_rect_header, FramebufferRectHeader, ENC_RAW,
    MSG_FRAMEBUFFER_UPDATE,
};
use helmhost_rfb::pixel_format::{raw_to_rgba, PixelFormat};

struct RecordingSink {
    damages: Vec<(Rect, Vec<u8>)>,
    size: Option<(u32, u32)>,
}

impl FrameSink for RecordingSink {
    fn on_desktop_resize(&mut self, w: u32, h: u32) {
        self.size = Some((w, h));
    }

    fn on_damage(&mut self, rect: Rect, rgba: &[u8]) {
        self.damages.push((rect, rgba.to_vec()));
    }
}

#[test]
fn fb_update_request_bytes() {
    let b = encode_fb_update_request(true, 0, 0, 100, 50);
    assert_eq!(b[0], 3);
    assert_eq!(b[1], 1);
    assert_eq!(&b[6..8], &100u16.to_be_bytes());
    assert_eq!(&b[8..10], &50u16.to_be_bytes());
}

#[test]
fn parse_fb_and_raw_to_sink() {
    let pf = PixelFormat::rgb888_le();
    // one red pixel: R=255 G=0 B=0 in LE 32bpp (R at shift 0)
    let pixel = [255u8, 0, 0, 0];
    let rgba = raw_to_rgba(&pf, 1, 1, &pixel).unwrap();
    assert_eq!(rgba, vec![255, 0, 0, 255]);

    let hdr = FramebufferRectHeader {
        x: 1,
        y: 2,
        w: 1,
        h: 1,
        encoding: ENC_RAW,
    };
    let mut sink = RecordingSink {
        damages: vec![],
        size: None,
    };
    apply_raw_rect(&pf, &hdr, &pixel, &mut sink).unwrap();
    assert_eq!(sink.damages.len(), 1);
    assert_eq!(sink.damages[0].0.x, 1);
    assert_eq!(sink.damages[0].1, vec![255, 0, 0, 255]);
}

#[test]
fn parse_headers() {
    let mut buf = vec![MSG_FRAMEBUFFER_UPDATE, 0];
    buf.extend_from_slice(&1u16.to_be_bytes());
    let (n, _) = parse_fb_update_header(&buf).unwrap();
    assert_eq!(n, 1);

    let mut rh = Vec::new();
    rh.extend_from_slice(&0u16.to_be_bytes());
    rh.extend_from_slice(&0u16.to_be_bytes());
    rh.extend_from_slice(&2u16.to_be_bytes());
    rh.extend_from_slice(&2u16.to_be_bytes());
    rh.extend_from_slice(&ENC_RAW.to_be_bytes());
    let (h, _) = parse_rect_header(&rh).unwrap();
    assert_eq!(h.w, 2);
    assert_eq!(h.encoding, ENC_RAW);
}

#[test]
fn pointer_and_key_encode() {
    let p = encode_pointer_event(PointerEvent {
        x: 10,
        y: 20,
        buttons: 1,
    });
    assert_eq!(p[0], 5);
    assert_eq!(p[1], 1);
    assert_eq!(&p[2..4], &10u16.to_be_bytes());

    let k = encode_key_event(KeyEvent {
        down: true,
        keysym: 0xff0d,
    });
    assert_eq!(k[0], 4);
    assert_eq!(k[1], 1);
    assert_eq!(&k[4..8], &0xff0du32.to_be_bytes());
}
