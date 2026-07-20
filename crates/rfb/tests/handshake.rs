//! Handshake / auth / ServerInit fixture tests (B1).

use helmhost_rfb::auth::encrypt_challenge;
use helmhost_rfb::handshake::{
    encode_client_init, encode_client_version, parse_security_result, parse_security_types,
    parse_server_init, parse_version, pick_security, SEC_NONE, SEC_UNIX_LOGIN, SEC_VNC_AUTH,
};
use helmhost_rfb::pixel_format::PixelFormat;

#[test]
fn parse_version_line() {
    let v = parse_version(b"RFB 003.008\n").unwrap();
    assert!(v.starts_with("RFB 003.008"));
    assert_eq!(encode_client_version(), *b"RFB 003.008\n");
}

#[test]
fn security_types_and_pick() {
    let types = parse_security_types(&[2, SEC_NONE, SEC_VNC_AUTH]).unwrap();
    assert_eq!(types, vec![SEC_NONE, SEC_VNC_AUTH]);
    assert_eq!(pick_security(&types, false, false).unwrap(), SEC_NONE);
    assert_eq!(pick_security(&types, true, false).unwrap(), SEC_VNC_AUTH);
}

#[test]
fn pick_unix_login_when_only_option() {
    let types = vec![SEC_UNIX_LOGIN];
    assert_eq!(pick_security(&types, false, false).unwrap(), SEC_UNIX_LOGIN);
}

#[test]
fn security_result_ok() {
    parse_security_result(&0u32.to_be_bytes()).unwrap();
    assert!(parse_security_result(&1u32.to_be_bytes()).is_err());
}

#[test]
fn server_init_roundtrip_shape() {
    let pf = PixelFormat::rgb888_le();
    let name = b"test-desktop";
    let mut buf = Vec::new();
    buf.extend_from_slice(&800u16.to_be_bytes());
    buf.extend_from_slice(&600u16.to_be_bytes());
    buf.extend_from_slice(&pf.encode());
    buf.extend_from_slice(&(name.len() as u32).to_be_bytes());
    buf.extend_from_slice(name);
    let init = parse_server_init(&buf).unwrap();
    assert_eq!(init.width, 800);
    assert_eq!(init.height, 600);
    assert_eq!(init.name, "test-desktop");
    assert_eq!(init.pixel_format, pf);
    assert_eq!(encode_client_init(true), [1]);
}

#[test]
fn vnc_auth_encrypt_changes_challenge() {
    let ch = [9u8; 16];
    let out = encrypt_challenge("secret", &ch);
    assert_ne!(out, ch);
}
