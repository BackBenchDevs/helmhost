//! VeNCrypt subtype negotiation (pre-TLS) fixture.

use helmhost_rfb::vencrypt::{negotiate_vencrypt_subtype, VENCRYPT_TLSNONE, VENCRYPT_TLSVNC};
use tokio::io::{AsyncReadExt, AsyncWriteExt, duplex};

#[tokio::test]
async fn vencrypt_negotiate_tlsnone() {
    let (mut client, mut server) = duplex(256);
    let server_task = tokio::spawn(async move {
        // Version 0.2
        server.write_all(&[0, 2]).await.unwrap();
        let mut client_ver = [0u8; 2];
        server.read_exact(&mut client_ver).await.unwrap();
        assert_eq!(client_ver, [0, 2]);
        // One subtype: TLSNone
        server.write_all(&[1]).await.unwrap();
        server
            .write_all(&VENCRYPT_TLSNONE.to_be_bytes())
            .await
            .unwrap();
        let mut chosen = [0u8; 4];
        server.read_exact(&mut chosen).await.unwrap();
        assert_eq!(u32::from_be_bytes(chosen), VENCRYPT_TLSNONE);
        server.write_all(&[1]).await.unwrap(); // OK
    });

    let subtype = negotiate_vencrypt_subtype(&mut client, false)
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

    let subtype = negotiate_vencrypt_subtype(&mut client, true)
        .await
        .unwrap();
    assert_eq!(subtype, VENCRYPT_TLSVNC);
    server_task.await.unwrap();
}

#[test]
fn tls_options_default_rejects_invalid_certs() {
    let opts = helmhost_rfb::TlsOptions::default();
    assert!(!opts.danger_accept_invalid_certs);
}
