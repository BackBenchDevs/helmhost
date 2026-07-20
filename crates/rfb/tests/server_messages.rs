//! Unknown server message + DesktopSize / LastRect / bounds (TigerVNC contracts).

use helmhost_core::{Creds, SessionEvent};
use helmhost_rfb::factory::connect_stream;
use helmhost_rfb::handshake::{SEC_NONE, SEC_RESULT_OK};
use helmhost_rfb::messages::{
    CLIENT_SET_ENCODINGS, CLIENT_SET_PIXEL_FORMAT, ENC_DESKTOP_SIZE, ENC_LAST_RECT, ENC_RAW,
    MSG_FRAMEBUFFER_UPDATE,
};
use helmhost_rfb::pixel_format::PixelFormat;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::time::{timeout, Duration};

async fn handshake_upto_fb_req(stream: &mut TcpStream) {
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
    stream.write_all(&4u16.to_be_bytes()).await.unwrap();
    stream.write_all(&4u16.to_be_bytes()).await.unwrap();
    stream.write_all(&pf.encode()).await.unwrap();
    stream.write_all(&4u32.to_be_bytes()).await.unwrap();
    stream.write_all(b"mock").await.unwrap();

    let mut spf = [0u8; 20];
    stream.read_exact(&mut spf).await.unwrap();
    assert_eq!(spf[0], CLIENT_SET_PIXEL_FORMAT);
    let mut enc_hdr = [0u8; 4];
    stream.read_exact(&mut enc_hdr).await.unwrap();
    assert_eq!(enc_hdr[0], CLIENT_SET_ENCODINGS);
    let n = u16::from_be_bytes([enc_hdr[2], enc_hdr[3]]) as usize;
    let mut encs = vec![0u8; n * 4];
    stream.read_exact(&mut encs).await.unwrap();
    let mut req = [0u8; 10];
    stream.read_exact(&mut req).await.unwrap();
}

#[tokio::test]
async fn desktop_resize_event() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let server = tokio::spawn(async move {
        let (mut stream, _) = listener.accept().await.unwrap();
        handshake_upto_fb_req(&mut stream).await;
        let mut msg = Vec::new();
        msg.push(MSG_FRAMEBUFFER_UPDATE);
        msg.push(0);
        msg.extend_from_slice(&1u16.to_be_bytes());
        msg.extend_from_slice(&0u16.to_be_bytes());
        msg.extend_from_slice(&0u16.to_be_bytes());
        msg.extend_from_slice(&8u16.to_be_bytes());
        msg.extend_from_slice(&6u16.to_be_bytes());
        msg.extend_from_slice(&ENC_DESKTOP_SIZE.to_be_bytes());
        stream.write_all(&msg).await.unwrap();
        let mut buf = [0u8; 32];
        let _ = timeout(Duration::from_millis(300), stream.read(&mut buf)).await;
    });

    let stream = TcpStream::connect(addr).await.unwrap();
    let mut handle = connect_stream(stream, &Creds::default()).await.unwrap();

    let mut saw = false;
    for _ in 0..10 {
        match timeout(Duration::from_millis(300), handle.events.recv()).await {
            Ok(Some(SessionEvent::DesktopResize { w: 8, h: 6 })) => {
                saw = true;
                break;
            }
            Ok(Some(_)) => continue,
            _ => break,
        }
    }
    assert!(saw);
    handle.close().await.ok();
    server.await.unwrap();
}

#[tokio::test]
async fn last_rect_ends_update_early() {
    // TigerVNC: nRects may be 0xFFFF; LastRect stops the update without reading more.
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let server = tokio::spawn(async move {
        let (mut stream, _) = listener.accept().await.unwrap();
        handshake_upto_fb_req(&mut stream).await;
        let mut msg = Vec::new();
        msg.push(MSG_FRAMEBUFFER_UPDATE);
        msg.push(0);
        msg.extend_from_slice(&0xFFFFu16.to_be_bytes());
        msg.extend_from_slice(&0u16.to_be_bytes());
        msg.extend_from_slice(&0u16.to_be_bytes());
        msg.extend_from_slice(&0u16.to_be_bytes());
        msg.extend_from_slice(&0u16.to_be_bytes());
        msg.extend_from_slice(&ENC_LAST_RECT.to_be_bytes());
        stream.write_all(&msg).await.unwrap();
        let mut req = [0u8; 10];
        timeout(Duration::from_millis(500), stream.read_exact(&mut req))
            .await
            .expect("timeout waiting for incremental FB request")
            .unwrap();
        assert_eq!(req[0], 3); // CLIENT_FB_UPDATE_REQUEST
    });

    let stream = TcpStream::connect(addr).await.unwrap();
    let mut handle = connect_stream(stream, &Creds::default()).await.unwrap();
    for _ in 0..5 {
        match timeout(Duration::from_millis(100), handle.events.recv()).await {
            Ok(Some(SessionEvent::Error(e))) => panic!("unexpected error: {e}"),
            Ok(Some(SessionEvent::Disconnected)) => break,
            Ok(Some(_)) => continue,
            _ => break,
        }
    }
    handle.close().await.ok();
    server.await.unwrap();
}

#[tokio::test]
async fn rect_past_framebuffer_emits_error() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let server = tokio::spawn(async move {
        let (mut stream, _) = listener.accept().await.unwrap();
        handshake_upto_fb_req(&mut stream).await;
        let mut msg = Vec::new();
        msg.push(MSG_FRAMEBUFFER_UPDATE);
        msg.push(0);
        msg.extend_from_slice(&1u16.to_be_bytes());
        msg.extend_from_slice(&0u16.to_be_bytes());
        msg.extend_from_slice(&0u16.to_be_bytes());
        msg.extend_from_slice(&8u16.to_be_bytes());
        msg.extend_from_slice(&8u16.to_be_bytes());
        msg.extend_from_slice(&ENC_RAW.to_be_bytes());
        stream.write_all(&msg).await.unwrap();
        let mut buf = [0u8; 32];
        let _ = timeout(Duration::from_millis(300), stream.read(&mut buf)).await;
    });

    let stream = TcpStream::connect(addr).await.unwrap();
    let mut handle = connect_stream(stream, &Creds::default()).await.unwrap();

    let mut saw = false;
    for _ in 0..10 {
        match timeout(Duration::from_millis(300), handle.events.recv()).await {
            Ok(Some(SessionEvent::Error(msg))) => {
                assert!(msg.contains("rect too big"), "{msg}");
                saw = true;
                break;
            }
            Ok(Some(SessionEvent::DesktopResize { .. })) => continue,
            Ok(Some(SessionEvent::Disconnected)) => break,
            Ok(Some(_)) => continue,
            _ => break,
        }
    }
    assert!(saw);
    server.await.unwrap();
}

#[tokio::test]
async fn unknown_server_message_emits_error() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let server = tokio::spawn(async move {
        let (mut stream, _) = listener.accept().await.unwrap();
        handshake_upto_fb_req(&mut stream).await;
        stream.write_all(&[99u8]).await.unwrap();
        let mut buf = [0u8; 32];
        let _ = timeout(Duration::from_millis(300), stream.read(&mut buf)).await;
    });

    let stream = TcpStream::connect(addr).await.unwrap();
    let mut handle = connect_stream(stream, &Creds::default()).await.unwrap();

    let mut saw_err = false;
    for _ in 0..10 {
        match timeout(Duration::from_millis(300), handle.events.recv()).await {
            Ok(Some(SessionEvent::Error(msg))) => {
                assert!(msg.contains("unknown"));
                saw_err = true;
                break;
            }
            Ok(Some(SessionEvent::DesktopResize { .. })) => continue,
            Ok(Some(SessionEvent::Disconnected)) => break,
            Ok(Some(_)) => continue,
            _ => break,
        }
    }
    assert!(saw_err);
    server.await.unwrap();
}
