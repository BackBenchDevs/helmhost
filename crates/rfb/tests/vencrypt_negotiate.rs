//! VeNCrypt subtype negotiation (pre-TLS) fixture.

use helmhost_core::NEED_USERNAME_PASSWORD;
use helmhost_rfb::vencrypt::{
    negotiate_vencrypt_subtype, pick_vencrypt_subtype, VENCRYPT_PLAIN, VENCRYPT_TLSNONE,
    VENCRYPT_TLSPLAIN, VENCRYPT_TLSVNC, VENCRYPT_X509NONE, VENCRYPT_X509PLAIN, VENCRYPT_X509VNC,
};
use tokio::io::{duplex, AsyncReadExt, AsyncWriteExt};
use tokio::time::{timeout, Duration};

#[test]
fn tiger_vnc_subtype_ids() {
    assert_eq!(VENCRYPT_PLAIN, 256);
    assert_eq!(VENCRYPT_TLSNONE, 257);
    assert_eq!(VENCRYPT_TLSVNC, 258);
    assert_eq!(VENCRYPT_TLSPLAIN, 259);
    assert_eq!(VENCRYPT_X509NONE, 260);
    assert_eq!(VENCRYPT_X509VNC, 261);
    assert_eq!(VENCRYPT_X509PLAIN, 262);
}

#[test]
fn pick_prefers_tlsplain_with_user_pass_when_no_x509() {
    let subs = [VENCRYPT_TLSNONE, VENCRYPT_TLSVNC, VENCRYPT_TLSPLAIN];
    assert_eq!(
        pick_vencrypt_subtype(&subs, true, true).unwrap(),
        VENCRYPT_TLSPLAIN
    );
}

#[test]
fn pick_prefers_x509plain_over_tlsplain() {
    let subs = [VENCRYPT_TLSPLAIN, VENCRYPT_X509PLAIN];
    assert_eq!(
        pick_vencrypt_subtype(&subs, true, true).unwrap(),
        VENCRYPT_X509PLAIN
    );
}

#[test]
fn pick_tlsvnc_with_password_only() {
    let subs = [VENCRYPT_TLSNONE, VENCRYPT_TLSVNC];
    assert_eq!(
        pick_vencrypt_subtype(&subs, false, true).unwrap(),
        VENCRYPT_TLSVNC
    );
}

#[test]
fn pick_prefers_x509vnc_over_tlsvnc() {
    let subs = [VENCRYPT_TLSVNC, VENCRYPT_X509VNC];
    assert_eq!(
        pick_vencrypt_subtype(&subs, false, true).unwrap(),
        VENCRYPT_X509VNC
    );
}

#[test]
fn pick_tlsnone_without_credentials() {
    let subs = [VENCRYPT_TLSNONE, VENCRYPT_PLAIN];
    assert_eq!(
        pick_vencrypt_subtype(&subs, false, false).unwrap(),
        VENCRYPT_TLSNONE
    );
}

#[test]
fn pick_prefers_x509none_over_tlsnone() {
    let subs = [VENCRYPT_TLSNONE, VENCRYPT_X509NONE];
    assert_eq!(
        pick_vencrypt_subtype(&subs, false, false).unwrap(),
        VENCRYPT_X509NONE
    );
}

#[test]
fn pick_plain_family_when_only_option() {
    // gcdvda-style: prefer X509Plain (rustls) over TLSPlain (anon).
    let subs = [VENCRYPT_TLSPLAIN, VENCRYPT_X509PLAIN];
    assert_eq!(
        pick_vencrypt_subtype(&subs, false, true).unwrap(),
        VENCRYPT_X509PLAIN
    );
    assert_eq!(
        pick_vencrypt_subtype(&subs, false, false).unwrap(),
        VENCRYPT_X509PLAIN
    );
}

#[tokio::test]
async fn vencrypt_negotiate_tlsnone() {
    let (mut client, mut server) = duplex(256);
    let server_task = tokio::spawn(async move {
        // Version 0.2
        server.write_all(&[0, 2]).await.unwrap();
        let mut client_ver = [0u8; 2];
        server.read_exact(&mut client_ver).await.unwrap();
        assert_eq!(client_ver, [0, 2]);
        // Version ACK (0 = OK) — required by TigerVNC wire format
        server.write_all(&[0]).await.unwrap();
        // One subtype: TLSNone (257)
        server.write_all(&[1]).await.unwrap();
        server
            .write_all(&VENCRYPT_TLSNONE.to_be_bytes())
            .await
            .unwrap();
        let mut chosen = [0u8; 4];
        server.read_exact(&mut chosen).await.unwrap();
        assert_eq!(u32::from_be_bytes(chosen), VENCRYPT_TLSNONE);
        server.write_all(&[1]).await.unwrap(); // subtype OK
    });

    let subtype = negotiate_vencrypt_subtype(&mut client, false, false)
        .await
        .unwrap();
    assert_eq!(subtype, VENCRYPT_TLSNONE);
    server_task.await.unwrap();
}

#[tokio::test]
async fn vencrypt_negotiate_prefers_tlsvnc_with_password() {
    let (mut client, mut server) = duplex(256);
    let server_task = tokio::spawn(async move {
        server.write_all(&[0, 2]).await.unwrap();
        let mut client_ver = [0u8; 2];
        server.read_exact(&mut client_ver).await.unwrap();
        server.write_all(&[0]).await.unwrap(); // version ACK
        server.write_all(&[2]).await.unwrap();
        server
            .write_all(&VENCRYPT_TLSNONE.to_be_bytes())
            .await
            .unwrap();
        server
            .write_all(&VENCRYPT_TLSVNC.to_be_bytes())
            .await
            .unwrap();
        let mut chosen = [0u8; 4];
        server.read_exact(&mut chosen).await.unwrap();
        assert_eq!(u32::from_be_bytes(chosen), VENCRYPT_TLSVNC);
        server.write_all(&[1]).await.unwrap();
    });

    let subtype = negotiate_vencrypt_subtype(&mut client, false, true)
        .await
        .unwrap();
    assert_eq!(subtype, VENCRYPT_TLSVNC);
    server_task.await.unwrap();
}

#[tokio::test]
async fn vencrypt_negotiate_prefers_tlsplain_with_user_pass() {
    let (mut client, mut server) = duplex(256);
    let server_task = tokio::spawn(async move {
        server.write_all(&[0, 2]).await.unwrap();
        let mut client_ver = [0u8; 2];
        server.read_exact(&mut client_ver).await.unwrap();
        server.write_all(&[0]).await.unwrap();
        server.write_all(&[3]).await.unwrap();
        for t in [VENCRYPT_TLSNONE, VENCRYPT_TLSVNC, VENCRYPT_TLSPLAIN] {
            server.write_all(&t.to_be_bytes()).await.unwrap();
        }
        let mut chosen = [0u8; 4];
        server.read_exact(&mut chosen).await.unwrap();
        assert_eq!(u32::from_be_bytes(chosen), VENCRYPT_TLSPLAIN);
        server.write_all(&[1]).await.unwrap();
    });

    let subtype = negotiate_vencrypt_subtype(&mut client, true, true)
        .await
        .unwrap();
    assert_eq!(subtype, VENCRYPT_TLSPLAIN);
    server_task.await.unwrap();
}

#[tokio::test]
async fn vencrypt_version_ack_zero_not_confused_with_subtype_count() {
    // Without reading version ACK, a 0-OK byte was misread as n=0 subtypes.
    let (mut client, mut server) = duplex(256);
    let server_task = tokio::spawn(async move {
        server.write_all(&[0, 2]).await.unwrap();
        let mut client_ver = [0u8; 2];
        server.read_exact(&mut client_ver).await.unwrap();
        server.write_all(&[0]).await.unwrap(); // ACK
        server.write_all(&[1]).await.unwrap();
        server
            .write_all(&VENCRYPT_TLSNONE.to_be_bytes())
            .await
            .unwrap();
        let mut chosen = [0u8; 4];
        server.read_exact(&mut chosen).await.unwrap();
        server.write_all(&[1]).await.unwrap();
    });

    let subtype = negotiate_vencrypt_subtype(&mut client, false, false)
        .await
        .unwrap();
    assert_eq!(subtype, VENCRYPT_TLSNONE);
    server_task.await.unwrap();
}

/// Plain-only server + no creds → NEED before writing subtype (avoids poisoning retry).
#[tokio::test]
async fn plain_only_no_creds_returns_need_without_writing_subtype() {
    let (mut client, mut server) = duplex(256);
    let server_task = tokio::spawn(async move {
        server.write_all(&[0, 2]).await.unwrap();
        let mut client_ver = [0u8; 2];
        server.read_exact(&mut client_ver).await.unwrap();
        server.write_all(&[0]).await.unwrap();
        server.write_all(&[2]).await.unwrap();
        server
            .write_all(&VENCRYPT_TLSPLAIN.to_be_bytes())
            .await
            .unwrap();
        server
            .write_all(&VENCRYPT_X509PLAIN.to_be_bytes())
            .await
            .unwrap();
        // Client must NOT send the chosen subtype U32.
        let mut chosen = [0u8; 4];
        let read = timeout(Duration::from_millis(80), server.read_exact(&mut chosen)).await;
        assert!(
            read.is_err(),
            "client must not write subtype before NEED_USERNAME_PASSWORD"
        );
    });

    let err = negotiate_vencrypt_subtype(&mut client, false, true)
        .await
        .unwrap_err();
    assert_eq!(err, NEED_USERNAME_PASSWORD);
    server_task.await.unwrap();
}

#[tokio::test]
async fn plain_only_with_user_pass_writes_x509plain() {
    let (mut client, mut server) = duplex(256);
    let server_task = tokio::spawn(async move {
        server.write_all(&[0, 2]).await.unwrap();
        let mut client_ver = [0u8; 2];
        server.read_exact(&mut client_ver).await.unwrap();
        server.write_all(&[0]).await.unwrap();
        server.write_all(&[2]).await.unwrap();
        server
            .write_all(&VENCRYPT_TLSPLAIN.to_be_bytes())
            .await
            .unwrap();
        server
            .write_all(&VENCRYPT_X509PLAIN.to_be_bytes())
            .await
            .unwrap();
        let mut chosen = [0u8; 4];
        server.read_exact(&mut chosen).await.unwrap();
        assert_eq!(u32::from_be_bytes(chosen), VENCRYPT_X509PLAIN);
        server.write_all(&[1]).await.unwrap();
    });

    let subtype = negotiate_vencrypt_subtype(&mut client, true, true)
        .await
        .unwrap();
    assert_eq!(subtype, VENCRYPT_X509PLAIN);
    server_task.await.unwrap();
}

#[test]
fn tls_options_default_rejects_invalid_certs() {
    let opts = helmhost_rfb::TlsOptions::default();
    assert!(!opts.danger_accept_invalid_certs);
}
