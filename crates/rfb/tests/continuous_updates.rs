//! Continuous Updates: advertise -313 → EoCU → EnableCU; no FBUR while CU on.

use helmhost_core::Creds;
use helmhost_rfb::factory::connect_stream;
use helmhost_rfb::handshake::{SEC_NONE, SEC_RESULT_OK};
use helmhost_rfb::messages::{
    CLIENT_ENABLE_CONTINUOUS_UPDATES, CLIENT_FB_UPDATE_REQUEST, CLIENT_SET_ENCODINGS,
    CLIENT_SET_PIXEL_FORMAT, ENC_RAW, MSG_END_OF_CONTINUOUS_UPDATES, MSG_FRAMEBUFFER_UPDATE,
};
use helmhost_rfb::pixel_format::PixelFormat;
use helmhost_rfb::ENC_CONTINUOUS_UPDATES;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::time::{timeout, Duration};

async fn handshake_read_encodings(stream: &mut TcpStream) -> Vec<i32> {
    stream.write_all(b"RFB 003.008\n").await.unwrap();
    let mut client_ver = [0u8; 12];
    stream.read_exact(&mut client_ver).await.unwrap();
    stream.write_all(&[1, SEC_NONE]).await.unwrap();
    let mut chosen = [0u8; 1];
    stream.read_exact(&mut chosen).await.unwrap();
    stream
        .write_all(&SEC_RESULT_OK.to_be_bytes())
        .await
        .unwrap();
    let mut shared = [0u8; 1];
    stream.read_exact(&mut shared).await.unwrap();

    let pf = PixelFormat::rgb888_le();
    stream.write_all(&2u16.to_be_bytes()).await.unwrap();
    stream.write_all(&1u16.to_be_bytes()).await.unwrap();
    stream.write_all(&pf.encode()).await.unwrap();
    stream.write_all(&2u32.to_be_bytes()).await.unwrap();
    stream.write_all(b"cu").await.unwrap();

    let mut spf = [0u8; 20];
    stream.read_exact(&mut spf).await.unwrap();
    assert_eq!(spf[0], CLIENT_SET_PIXEL_FORMAT);

    let mut enc_hdr = [0u8; 4];
    stream.read_exact(&mut enc_hdr).await.unwrap();
    assert_eq!(enc_hdr[0], CLIENT_SET_ENCODINGS);
    let n = u16::from_be_bytes([enc_hdr[2], enc_hdr[3]]) as usize;
    let mut encs_raw = vec![0u8; n * 4];
    stream.read_exact(&mut encs_raw).await.unwrap();
    let mut encs = Vec::with_capacity(n);
    for chunk in encs_raw.chunks_exact(4) {
        encs.push(i32::from_be_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]));
    }

    let mut req = [0u8; 10];
    stream.read_exact(&mut req).await.unwrap();
    assert_eq!(req[0], CLIENT_FB_UPDATE_REQUEST);
    encs
}

fn raw_fbu_2x1() -> Vec<u8> {
    let pf = PixelFormat::rgb888_le();
    let mut msg = Vec::new();
    msg.push(MSG_FRAMEBUFFER_UPDATE);
    msg.push(0);
    msg.extend_from_slice(&1u16.to_be_bytes());
    msg.extend_from_slice(&0u16.to_be_bytes());
    msg.extend_from_slice(&0u16.to_be_bytes());
    msg.extend_from_slice(&2u16.to_be_bytes());
    msg.extend_from_slice(&1u16.to_be_bytes());
    msg.extend_from_slice(&ENC_RAW.to_be_bytes());
    for _ in 0..2 {
        let mut pix = vec![0u8; pf.bytes_per_pixel()];
        pix[0] = 1;
        msg.extend_from_slice(&pix);
    }
    msg
}

#[tokio::test]
async fn continuous_updates_skips_fbur_after_eocu() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let server = tokio::spawn(async move {
        let (mut stream, _) = listener.accept().await.unwrap();
        let encs = handshake_read_encodings(&mut stream).await;
        assert!(
            encs.contains(&ENC_CONTINUOUS_UPDATES),
            "client must advertise ContinuousUpdates (-313), got {encs:?}"
        );

        // EndOfContinuousUpdates (type byte only).
        stream
            .write_all(&[MSG_END_OF_CONTINUOUS_UPDATES])
            .await
            .unwrap();

        // Client EnableContinuousUpdates(true, full desktop).
        let mut enable = [0u8; 10];
        stream.read_exact(&mut enable).await.unwrap();
        assert_eq!(enable[0], CLIENT_ENABLE_CONTINUOUS_UPDATES);
        assert_eq!(enable[1], 1);
        assert_eq!(&enable[6..8], &2u16.to_be_bytes());
        assert_eq!(&enable[8..10], &1u16.to_be_bytes());

        // FBU while CU active — client must NOT send FBUR.
        stream.write_all(&raw_fbu_2x1()).await.unwrap();

        let mut buf = [0u8; 32];
        match timeout(Duration::from_millis(400), stream.read(&mut buf)).await {
            Ok(Ok(n)) if n > 0 => {
                assert_ne!(
                    buf[0], CLIENT_FB_UPDATE_REQUEST,
                    "must not RequestUpdate while Continuous Updates enabled; got {:?}",
                    &buf[..n]
                );
            }
            _ => {} // timeout / EOF = no FBUR, success
        }
    });

    let stream = TcpStream::connect(addr).await.unwrap();
    let mut handle = connect_stream(stream, &Creds::default()).await.unwrap();

    let deadline = tokio::time::Instant::now() + Duration::from_secs(2);
    let mut saw_dirty = false;
    while tokio::time::Instant::now() < deadline {
        match timeout(Duration::from_millis(200), handle.events.recv()).await {
            Ok(Some(helmhost_core::SessionEvent::FramebufferDirty { .. })) => {
                saw_dirty = true;
                break;
            }
            Ok(Some(_)) => continue,
            Ok(None) => break,
            Err(_) => continue,
        }
    }
    assert!(saw_dirty, "expected dirty after CU FBU");

    handle.close().await.ok();
    server.await.unwrap();
}
