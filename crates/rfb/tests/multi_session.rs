//! Two concurrent mock sessions + close + SessionManager tracking.

use helmhost_core::{
    Creds, HelmRuntime, SessionCommand, SessionEvent, SessionId, SessionManager, DEFAULT_QUEUE_CAPACITY,
};
use helmhost_rfb::session::connect_any;
use helmhost_rfb::handshake::{SEC_NONE, SEC_RESULT_OK};
use helmhost_rfb::messages::{CLIENT_SET_ENCODINGS, CLIENT_SET_PIXEL_FORMAT, ENC_RAW, MSG_FRAMEBUFFER_UPDATE};
use helmhost_rfb::pixel_format::PixelFormat;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt, duplex};
use tokio::sync::mpsc;
use tokio::time::{timeout, Duration};

async fn mock_peer_half(mut server: impl AsyncReadExt + AsyncWriteExt + Unpin) {
    server.write_all(b"RFB 003.008\n").await.unwrap();
    let mut v = [0u8; 12];
    server.read_exact(&mut v).await.unwrap();
    server.write_all(&[1, SEC_NONE]).await.unwrap();
    let mut c = [0u8; 1];
    server.read_exact(&mut c).await.unwrap();
    server
        .write_all(&SEC_RESULT_OK.to_be_bytes())
        .await
        .unwrap();
    let mut s = [0u8; 1];
    server.read_exact(&mut s).await.unwrap();
    let pf = PixelFormat::rgb888_le();
    server.write_all(&2u16.to_be_bytes()).await.unwrap();
    server.write_all(&1u16.to_be_bytes()).await.unwrap();
    server.write_all(&pf.encode()).await.unwrap();
    server.write_all(&1u32.to_be_bytes()).await.unwrap();
    server.write_all(b"m").await.unwrap();
    let mut spf = [0u8; 20];
    server.read_exact(&mut spf).await.unwrap();
    assert_eq!(spf[0], CLIENT_SET_PIXEL_FORMAT);
    let mut enc = [0u8; 4];
    server.read_exact(&mut enc).await.unwrap();
    assert_eq!(enc[0], CLIENT_SET_ENCODINGS);
    let n = u16::from_be_bytes([enc[2], enc[3]]) as usize;
    let mut encs = vec![0u8; n * 4];
    server.read_exact(&mut encs).await.unwrap();
    let mut req = [0u8; 10];
    server.read_exact(&mut req).await.unwrap();

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
        msg.extend_from_slice(&[0, 0, 255, 0]);
    }
    server.write_all(&msg).await.unwrap();
    let mut buf = [0u8; 64];
    let _ = timeout(Duration::from_millis(500), server.read(&mut buf)).await;
}

async fn wait_damage(handle: &mut helmhost_core::SessionHandle) -> bool {
    for _ in 0..20 {
        match timeout(Duration::from_millis(100), handle.events.recv()).await {
            Ok(Some(SessionEvent::Damage { .. })) => return true,
            Ok(Some(_)) => continue,
            _ => return false,
        }
    }
    false
}

#[tokio::test]
async fn two_concurrent_mock_sessions() {
    let (c1, s1) = duplex(4096);
    let (c2, s2) = duplex(4096);
    tokio::spawn(async move { mock_peer_half(s1).await });
    tokio::spawn(async move { mock_peer_half(s2).await });

    let mut h1 = connect_any(SessionId(1), c1, &Creds::default())
        .await
        .unwrap();
    let mut h2 = connect_any(SessionId(2), c2, &Creds::default())
        .await
        .unwrap();

    assert!(wait_damage(&mut h1).await);
    assert!(wait_damage(&mut h2).await);

    h1.close().await.unwrap();
    h2.close().await.unwrap();
}

#[tokio::test]
async fn session_manager_close_sends_command() {
    let mut mgr = SessionManager::new();
    let id = mgr.alloc_id();
    let (tx, mut rx) = mpsc::channel(4);
    mgr.insert(id, tx);
    mgr.close(id).await.unwrap();
    assert_eq!(rx.recv().await, Some(SessionCommand::Close));
    assert!(!mgr.contains(id));
}

#[test]
fn helm_runtime_hosts_two_tasks() {
    let rt = HelmRuntime::new().unwrap();
    let n = Arc::new(AtomicUsize::new(0));
    let a = Arc::clone(&n);
    let b = Arc::clone(&n);
    let h1 = rt.spawn(async move {
        a.fetch_add(1, Ordering::SeqCst);
    });
    let h2 = rt.spawn(async move {
        b.fetch_add(1, Ordering::SeqCst);
    });
    rt.handle().block_on(async {
        h1.await.unwrap();
        h2.await.unwrap();
    });
    assert_eq!(n.load(Ordering::SeqCst), 2);
}

#[tokio::test]
async fn close_stops_accepting_commands() {
    let (client, server) = duplex(4096);
    tokio::spawn(async move { mock_peer_half(server).await });
    let mut handle = connect_any(SessionId(9), client, &Creds::default())
        .await
        .unwrap();
    assert!(wait_damage(&mut handle).await);
    let cmd = handle.commands.clone();
    handle.send(SessionCommand::Close).await.unwrap();
    // Wait for writer task to exit and drop receiver
    tokio::time::sleep(Duration::from_millis(50)).await;
    let err = cmd
        .send(SessionCommand::RequestUpdate { incremental: true })
        .await;
    assert!(err.is_err());
}

#[test]
fn damage_coalesce_drops_when_full() {
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    rt.block_on(async {
        let (tx, mut rx) = mpsc::channel::<SessionEvent>(1);
        tx.try_send(SessionEvent::Damage {
            rect: helmhost_core::Rect {
                x: 0,
                y: 0,
                w: 1,
                h: 1,
            },
            rgba: vec![1, 2, 3, 4],
        })
        .unwrap();
        let full = tx.try_send(SessionEvent::Damage {
            rect: helmhost_core::Rect {
                x: 0,
                y: 0,
                w: 1,
                h: 1,
            },
            rgba: vec![5, 6, 7, 8],
        });
        assert!(full.is_err());
        let _ = rx.recv().await;
        assert_eq!(DEFAULT_QUEUE_CAPACITY, 64);
    });
}

#[tokio::test]
async fn unknown_zero_area_encoding_skipped() {
    use helmhost_rfb::factory::connect_stream;
    use helmhost_rfb::handshake::{SEC_NONE, SEC_RESULT_OK};
    use helmhost_rfb::messages::{
        CLIENT_SET_ENCODINGS, CLIENT_SET_PIXEL_FORMAT, ENC_RAW, MSG_FRAMEBUFFER_UPDATE,
    };
    use tokio::net::{TcpListener, TcpStream};

    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let server = tokio::spawn(async move {
        let (mut stream, _) = listener.accept().await.unwrap();
        stream.write_all(b"RFB 003.008\n").await.unwrap();
        let mut v = [0u8; 12];
        stream.read_exact(&mut v).await.unwrap();
        stream.write_all(&[1, SEC_NONE]).await.unwrap();
        let mut c = [0u8; 1];
        stream.read_exact(&mut c).await.unwrap();
        stream
            .write_all(&SEC_RESULT_OK.to_be_bytes())
            .await
            .unwrap();
        let mut s = [0u8; 1];
        stream.read_exact(&mut s).await.unwrap();
        let pf = PixelFormat::rgb888_le();
        stream.write_all(&2u16.to_be_bytes()).await.unwrap();
        stream.write_all(&1u16.to_be_bytes()).await.unwrap();
        stream.write_all(&pf.encode()).await.unwrap();
        stream.write_all(&1u32.to_be_bytes()).await.unwrap();
        stream.write_all(b"m").await.unwrap();
        let mut spf = [0u8; 20];
        stream.read_exact(&mut spf).await.unwrap();
        assert_eq!(spf[0], CLIENT_SET_PIXEL_FORMAT);
        let mut enc = [0u8; 4];
        stream.read_exact(&mut enc).await.unwrap();
        assert_eq!(enc[0], CLIENT_SET_ENCODINGS);
        let n = u16::from_be_bytes([enc[2], enc[3]]) as usize;
        let mut encs = vec![0u8; n * 4];
        stream.read_exact(&mut encs).await.unwrap();
        let mut req = [0u8; 10];
        stream.read_exact(&mut req).await.unwrap();

        // FB update: unknown encoding with 0x0 area, then Raw
        let mut msg = Vec::new();
        msg.push(MSG_FRAMEBUFFER_UPDATE);
        msg.push(0);
        msg.extend_from_slice(&2u16.to_be_bytes());
        // unknown encoding, zero area
        msg.extend_from_slice(&0u16.to_be_bytes());
        msg.extend_from_slice(&0u16.to_be_bytes());
        msg.extend_from_slice(&0u16.to_be_bytes());
        msg.extend_from_slice(&0u16.to_be_bytes());
        msg.extend_from_slice(&9999i32.to_be_bytes());
        // raw 2x1
        msg.extend_from_slice(&0u16.to_be_bytes());
        msg.extend_from_slice(&0u16.to_be_bytes());
        msg.extend_from_slice(&2u16.to_be_bytes());
        msg.extend_from_slice(&1u16.to_be_bytes());
        msg.extend_from_slice(&ENC_RAW.to_be_bytes());
        for _ in 0..2 {
            msg.extend_from_slice(&[0, 0, 255, 0]);
        }
        stream.write_all(&msg).await.unwrap();
        let mut buf = [0u8; 64];
        let _ = timeout(Duration::from_millis(500), stream.read(&mut buf)).await;
    });

    let stream = TcpStream::connect(addr).await.unwrap();
    let mut handle = connect_stream(stream, &Creds::default()).await.unwrap();
    assert!(wait_damage(&mut handle).await);
    handle.close().await.ok();
    server.await.unwrap();
}

