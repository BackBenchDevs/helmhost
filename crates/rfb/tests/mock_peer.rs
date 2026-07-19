//! Mock TCP peer: handshake → Raw update → pointer (async queues).

use helmhost_core::{Creds, PointerEvent, SessionCommand, SessionEvent};
use helmhost_rfb::factory::connect_stream;
use helmhost_rfb::handshake::{SEC_NONE, SEC_RESULT_OK};
use helmhost_rfb::messages::{
    CLIENT_SET_ENCODINGS, CLIENT_SET_PIXEL_FORMAT, ENC_RAW, MSG_FRAMEBUFFER_UPDATE,
};
use helmhost_rfb::pixel_format::PixelFormat;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::time::{timeout, Duration};

async fn write_server_init(stream: &mut TcpStream, w: u16, h: u16, name: &str) {
    let pf = PixelFormat::rgb888_le();
    stream.write_all(&w.to_be_bytes()).await.unwrap();
    stream.write_all(&h.to_be_bytes()).await.unwrap();
    stream.write_all(&pf.encode()).await.unwrap();
    stream
        .write_all(&(name.len() as u32).to_be_bytes())
        .await
        .unwrap();
    stream.write_all(name.as_bytes()).await.unwrap();
}

async fn mock_server(mut stream: TcpStream) {
    stream.write_all(b"RFB 003.008\n").await.unwrap();
    let mut client_ver = [0u8; 12];
    stream.read_exact(&mut client_ver).await.unwrap();

    stream.write_all(&[1, SEC_NONE]).await.unwrap();
    let mut chosen = [0u8; 1];
    stream.read_exact(&mut chosen).await.unwrap();
    assert_eq!(chosen[0], SEC_NONE);

    stream
        .write_all(&SEC_RESULT_OK.to_be_bytes())
        .await
        .unwrap();

    let mut shared = [0u8; 1];
    stream.read_exact(&mut shared).await.unwrap();

    write_server_init(&mut stream, 2, 1, "mock").await;

    // SetPixelFormat (20)
    let mut spf = [0u8; 20];
    stream.read_exact(&mut spf).await.unwrap();
    assert_eq!(spf[0], CLIENT_SET_PIXEL_FORMAT);

    // SetEncodings
    let mut enc_hdr = [0u8; 4];
    stream.read_exact(&mut enc_hdr).await.unwrap();
    assert_eq!(enc_hdr[0], CLIENT_SET_ENCODINGS);
    let n = u16::from_be_bytes([enc_hdr[2], enc_hdr[3]]) as usize;
    let mut encs = vec![0u8; n * 4];
    stream.read_exact(&mut encs).await.unwrap();

    // First FB update request
    let mut req = [0u8; 10];
    stream.read_exact(&mut req).await.unwrap();
    assert_eq!(req[0], 3);

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
        pix[2] = 255;
        msg.extend_from_slice(&pix);
    }
    stream.write_all(&msg).await.unwrap();

    // Incremental request + optional pointer
    let mut buf = [0u8; 64];
    let _ = timeout(Duration::from_millis(500), stream.read(&mut buf)).await;
    let _ = timeout(Duration::from_millis(500), stream.read(&mut buf)).await;
}

#[tokio::test]
async fn mock_peer_handshake_raw_and_pointer() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let server = tokio::spawn(async move {
        let (stream, _) = listener.accept().await.unwrap();
        mock_server(stream).await;
    });

    let stream = TcpStream::connect(addr).await.unwrap();
    let mut handle = connect_stream(stream, &Creds::default())
        .await
        .expect("handshake");
    assert_eq!((handle.width, handle.height), (2, 1));

    let mut saw_damage = false;
    let deadline = tokio::time::Instant::now() + Duration::from_secs(2);
    while tokio::time::Instant::now() < deadline {
        match timeout(Duration::from_millis(200), handle.events.recv()).await {
            Ok(Some(SessionEvent::Damage { .. })) => {
                saw_damage = true;
                break;
            }
            Ok(Some(SessionEvent::DesktopResize { .. })) => continue,
            Ok(Some(_)) => continue,
            Ok(None) => break,
            Err(_) => continue,
        }
    }
    assert!(saw_damage, "expected Damage event");

    handle
        .send(SessionCommand::Pointer(PointerEvent {
            x: 1,
            y: 0,
            buttons: 0,
        }))
        .await
        .unwrap();
    handle.close().await.unwrap();
    server.await.unwrap();
}

#[tokio::test]
#[ignore = "requires local RFB server; set HELMHOST_RFB=host:port"]
async fn live_rfb_optional() {
    use helmhost_core::{ConnectTarget, SessionFactory};
    use helmhost_rfb::RfbSessionFactory;

    let endpoint = std::env::var("HELMHOST_RFB").unwrap_or_else(|_| "127.0.0.1:5900".into());
    let (host, port) = match endpoint.rsplit_once(':') {
        Some((h, p)) => (h.to_string(), p.parse().expect("port")),
        None => (endpoint, 5900u16),
    };

    let factory = RfbSessionFactory::new();
    let mut handle = factory
        .connect(
            ConnectTarget { host, port },
            Creds {
                password: std::env::var("HELMHOST_RFB_PASSWORD").ok(),
            },
        )
        .await
        .expect("live connect");

    let _ = handle
        .send(SessionCommand::RequestUpdate { incremental: false })
        .await;
    let _ = timeout(Duration::from_secs(3), handle.events.recv()).await;
    handle.close().await.ok();
}
