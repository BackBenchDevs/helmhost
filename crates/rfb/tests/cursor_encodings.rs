//! Cursor pseudo-encoding advertise + decode smoke tests.

use helmhost_rfb::cursor::{decode_cursor_with_alpha, decode_xcursor};
use helmhost_rfb::{
    preferred_encodings, ENC_CURSOR, ENC_CURSOR_WITH_ALPHA, ENC_XCURSOR,
};

#[test]
fn preferred_encodings_advertise_local_cursors() {
    let e = preferred_encodings();
    let alpha = e.iter().position(|&x| x == ENC_CURSOR_WITH_ALPHA).unwrap();
    let cursor = e.iter().position(|&x| x == ENC_CURSOR).unwrap();
    let xcursor = e.iter().position(|&x| x == ENC_XCURSOR).unwrap();
    assert!(alpha < cursor && cursor < xcursor);
}

#[test]
fn decode_alpha_fixture_emits_rgba() {
    let mut data = vec![0u8, 0, 0, 0];
    data.extend_from_slice(&[255, 0, 0, 255]);
    let c = decode_cursor_with_alpha(1, 1, 2, 3, &data).unwrap();
    assert_eq!(c.rgba, vec![255, 0, 0, 255]);
    assert_eq!(c.hotspot_x, 2);
    assert_eq!(c.hotspot_y, 3);
}

#[test]
fn decode_xcursor_fixture() {
    let mut data = vec![255, 0, 0, 0, 255, 0]; // fg red, bg green
    data.push(0b1000_0000);
    data.push(0b1000_0000);
    let c = decode_xcursor(1, 1, 0, 0, &data).unwrap();
    assert_eq!(&c.rgba[..4], &[255, 0, 0, 255]);
}
