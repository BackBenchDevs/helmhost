//! Raw / CopyRect / encodings unit tests.

use helmhost_core::{KeyEvent, PointerEvent, Rect};
use helmhost_rfb::fb_cache::FramebufferCache;
use helmhost_rfb::messages::{
    apply_raw_rect, encode_client_cut_text, encode_fb_update_request, encode_key_event,
    encode_pointer_event, parse_fb_update_header, parse_rect_header, preferred_encodings,
    FramebufferRectHeader, ENC_COPYRECT, ENC_DESKTOP_SIZE, ENC_EXTENDED_DESKTOP_SIZE,
    ENC_LAST_RECT, ENC_RAW, ENC_ZRLE, MSG_FRAMEBUFFER_UPDATE,
};
use helmhost_rfb::pixel_format::{raw_to_rgba, PixelFormat};
use helmhost_rfb::zrle::decode_zrle;

#[test]
fn fb_update_request_bytes() {
    let b = encode_fb_update_request(true, 0, 0, 100, 50);
    assert_eq!(b[0], 3);
    assert_eq!(b[1], 1);
    assert_eq!(&b[6..8], &100u16.to_be_bytes());
    assert_eq!(&b[8..10], &50u16.to_be_bytes());
}

#[test]
fn parse_fb_and_raw() {
    let pf = PixelFormat::rgb888_le();
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
    let (rect, out) = apply_raw_rect(&pf, &hdr, &pixel).unwrap();
    assert_eq!(rect.x, 1);
    assert_eq!(out, vec![255, 0, 0, 255]);
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

#[test]
fn preferred_encodings_order() {
    assert_eq!(
        preferred_encodings(),
        [
            ENC_ZRLE,
            ENC_RAW,
            ENC_COPYRECT,
            ENC_DESKTOP_SIZE,
            ENC_EXTENDED_DESKTOP_SIZE,
            ENC_LAST_RECT
        ]
    );
}

#[test]
fn copyrect_via_cache() {
    let mut cache = FramebufferCache::new(4, 2);
    let red = vec![255u8, 0, 0, 255, 255, 0, 0, 255];
    cache
        .put_damage(
            Rect {
                x: 0,
                y: 0,
                w: 2,
                h: 1,
            },
            &red,
        )
        .unwrap();
    cache
        .copy_rect(
            Rect {
                x: 2,
                y: 0,
                w: 2,
                h: 1,
            },
            0,
            0,
        )
        .unwrap();
    let mut out = vec![0u8; cache.byte_len()];
    cache.copy_to(&mut out).unwrap();
    // Row 0: red, red, red, red (first 16 bytes of two copied pixels at x=2)
    assert_eq!(&out[8..16], &red[..]);
}

#[test]
fn fb_copy_solid_color() {
    let mut cache = FramebufferCache::new(2, 2);
    let blue = vec![0u8, 0, 255, 255];
    for y in 0..2 {
        for x in 0..2 {
            cache.put_damage(Rect { x, y, w: 1, h: 1 }, &blue).unwrap();
        }
    }
    let mut out = vec![0u8; 16];
    cache.copy_to(&mut out).unwrap();
    assert_eq!(&out[0..4], &blue[..]);
    assert_eq!(&out[12..16], &blue[..]);
}

#[test]
fn fb_copy_short_buffer_errors() {
    let cache = FramebufferCache::new(2, 2);
    let mut short = vec![0u8; 8];
    assert!(cache.copy_to(&mut short).is_err());
}

#[test]
fn put_damage_short_rgba_errors() {
    let mut cache = FramebufferCache::new(2, 2);
    let err = cache.put_damage(
        Rect {
            x: 0,
            y: 0,
            w: 1,
            h: 1,
        },
        &[1, 2, 3],
    );
    assert!(err.is_err());
}

#[test]
fn zrle_fixture_file() {
    let pf = PixelFormat::rgb888_le();
    let data = include_bytes!("fixtures/zrle_2x2_solid.bin");
    let rgba = decode_zrle(&pf, 2, 2, data).unwrap();
    assert_eq!(rgba.len(), 16);
    assert_eq!(&rgba[0..3], &[10, 20, 30]);
}

#[test]
fn client_cut_text_encode() {
    let b = encode_client_cut_text("hi");
    assert_eq!(b[0], 6);
    assert_eq!(&b[4..8], &2u32.to_be_bytes());
    assert_eq!(&b[8..], b"hi");
}
