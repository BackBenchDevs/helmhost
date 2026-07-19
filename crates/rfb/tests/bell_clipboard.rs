//! Bell + ServerCutText → queued SessionEvents; ClientCutText command.

use helmhost_core::{Creds, SessionCommand, SessionEvent};
use helmhost_rfb::factory::connect_stream;
use helmhost_rfb::handshake::{SEC_NONE, SEC_RESULT_OK};
use helmhost_rfb::messages::{
    CLIENT_CUT_TEXT, CLIENT_SET_ENCODINGS, CLIENT_SET_PIXEL_FORMAT, MSG_BELL, MSG_SERVER_CUT_TEXT,
};
use helmhost_rfb::pixel_format::PixelFormat;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::time::{timeout, Duration};

async fn handshake_upto_fb_req(stream: &mut TcpStream) {
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
    stream.write_all(&1u16.to_be_bytes()).await.unwrap();
    stream.write_all(&1u16.to_be_bytes()).await.unwrap();
    stream.write_all(&pf.encode()).await.unwrap();
    stream.write_all(&1u32.to_be_bytes()).await.unwrap();
    stream.write_all(b"x").await.unwrap();
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
}

#[tokio::test]
async fn bell_and_clipboard_events() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let server = tokio::spawn(async move {
        let (mut stream, _) = listener.accept().await.unwrap();
        handshake_upto_fb_req(&mut stream).await;
        stream.write_all(&[MSG_BELL]).await.unwrap();
        let mut cut = vec![MSG_SERVER_CUT_TEXT, 0, 0, 0];
        cut.extend_from_slice(&3u32.to_be_bytes());
        cut.extend_from_slice(b"abc");
        stream.write_all(&cut).await.unwrap();
        // Expect ClientCutText from client
        let mut hdr = [0u8; 8];
        timeout(Duration::from_secs(1), stream.read_exact(&mut hdr))
            .await
            .unwrap()
            .unwrap();
        assert_eq!(hdr[0], CLIENT_CUT_TEXT);
        let len = u32::from_be_bytes([hdr[4], hdr[5], hdr[6], hdr[7]]) as usize;
        let mut body = vec![0u8; len];
        stream.read_exact(&mut body).await.unwrap();
        assert_eq!(&body, b"xyz");
    });

    let stream = TcpStream::connect(addr).await.unwrap();
    let mut handle = connect_stream(stream, &Creds::default()).await.unwrap();

    let mut bell = false;
    let mut clip = false;
    for _ in 0..20 {
        match timeout(Duration::from_millis(200), handle.events.recv()).await {
            Ok(Some(SessionEvent::Bell)) => bell = true,
            Ok(Some(SessionEvent::Clipboard(t))) if t == "abc" => clip = true,
            Ok(Some(SessionEvent::DesktopResize { .. })) => {}
            Ok(Some(_)) => {}
            _ => break,
        }
        if bell && clip {
            break;
        }
    }
    assert!(bell && clip);

    handle
        .send(SessionCommand::CutText("xyz".into()))
        .await
        .unwrap();
    handle.close().await.ok();
    server.await.unwrap();
}
