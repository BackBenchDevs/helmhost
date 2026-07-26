//! Handshake / auth / ServerInit fixture tests (B1).

use helmhost_core::Creds;
use helmhost_rfb::auth::encrypt_challenge;
use helmhost_rfb::handshake::{
    encode_client_init, encode_client_version, encode_unix_login, handshake_security_and_init,
    parse_security_result, parse_security_types, parse_server_init, parse_version, pick_security,
    unix_login_exchange, SEC_NONE, SEC_RESULT_OK, SEC_UNIX_LOGIN, SEC_VNC_AUTH,
};
use helmhost_rfb::pixel_format::PixelFormat;
use tokio::io::{duplex, AsyncReadExt, AsyncWriteExt};

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

#[test]
fn encode_unix_login_lengths_then_utf8() {
    let buf = encode_unix_login("alice", "sëcret");
    assert_eq!(&buf[0..4], &5u32.to_be_bytes());
    assert_eq!(&buf[4..8], &7u32.to_be_bytes()); // "sëcret" is 7 UTF-8 bytes
    assert_eq!(&buf[8..13], b"alice");
    assert_eq!(&buf[13..], "sëcret".as_bytes());
}

#[tokio::test]
async fn unix_login_exchange_writes_payload() {
    let (mut client, mut server) = duplex(256);
    let expected = encode_unix_login("lab", "pw");
    let server_task = tokio::spawn(async move {
        let mut got = vec![0u8; expected.len()];
        server.read_exact(&mut got).await.unwrap();
        assert_eq!(got, expected);
    });
    unix_login_exchange(&mut client, "lab", "pw").await.unwrap();
    server_task.await.unwrap();
}

#[tokio::test]
async fn handshake_unix_login_full_path() {
    let (mut client, mut server) = duplex(4096);
    let name = b"unix-desk";
    let pf = PixelFormat::rgb888_le();

    let server_task = tokio::spawn(async move {
        server.write_all(b"RFB 003.008\n").await.unwrap();
        let mut client_ver = [0u8; 12];
        server.read_exact(&mut client_ver).await.unwrap();
        assert_eq!(&client_ver, b"RFB 003.008\n");

        server.write_all(&[1, SEC_UNIX_LOGIN]).await.unwrap();
        let mut chosen = [0u8; 1];
        server.read_exact(&mut chosen).await.unwrap();
        assert_eq!(chosen[0], SEC_UNIX_LOGIN);

        let expected = encode_unix_login("bob", "secret");
        let mut creds = vec![0u8; expected.len()];
        server.read_exact(&mut creds).await.unwrap();
        assert_eq!(creds, expected);

        server
            .write_all(&SEC_RESULT_OK.to_be_bytes())
            .await
            .unwrap();

        let mut client_init = [0u8; 1];
        server.read_exact(&mut client_init).await.unwrap();
        assert_eq!(client_init[0], 1);

        let mut init = Vec::new();
        init.extend_from_slice(&640u16.to_be_bytes());
        init.extend_from_slice(&480u16.to_be_bytes());
        init.extend_from_slice(&pf.encode());
        init.extend_from_slice(&(name.len() as u32).to_be_bytes());
        init.extend_from_slice(name);
        server.write_all(&init).await.unwrap();
    });

    let creds = Creds {
        username: Some("bob".into()),
        password: Some("secret".into()),
    };
    let (init, venc) = handshake_security_and_init(&mut client, &creds, false)
        .await
        .unwrap();
    assert!(venc.is_none());
    assert_eq!(init.width, 640);
    assert_eq!(init.height, 480);
    assert_eq!(init.name, "unix-desk");
    server_task.await.unwrap();
}

#[tokio::test]
async fn handshake_unix_login_needs_username_password() {
    let (mut client, mut server) = duplex(512);
    let server_task = tokio::spawn(async move {
        server.write_all(b"RFB 003.008\n").await.unwrap();
        let mut client_ver = [0u8; 12];
        server.read_exact(&mut client_ver).await.unwrap();
        server.write_all(&[1, SEC_UNIX_LOGIN]).await.unwrap();
    });

    let creds = Creds {
        username: None,
        password: None,
    };
    let err = handshake_security_and_init(&mut client, &creds, false)
        .await
        .unwrap_err();
    assert!(err.contains("NEED_USERNAME_PASSWORD"));
    let _ = server_task.await;
}
