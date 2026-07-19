//! Mock TCP peer: handshake → one Raw update → pointer (B4).

use helmhost_core::{Creds, FrameSink, PointerEvent, Rect};
use helmhost_rfb::factory::connect_stream;
use helmhost_rfb::handshake::{SEC_NONE, SEC_RESULT_OK};
use helmhost_rfb::messages::{ENC_RAW, MSG_FRAMEBUFFER_UPDATE};
use helmhost_rfb::pixel_format::PixelFormat;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::thread;
use std::time::Duration;

struct RecSink {
    damages: usize,
}

impl FrameSink for RecSink {
    fn on_desktop_resize(&mut self, _w: u32, _h: u32) {}
    fn on_damage(&mut self, _rect: Rect, _rgba: &[u8]) {
        self.damages += 1;
    }
}

fn write_server_init(stream: &mut TcpStream, w: u16, h: u16, name: &str) {
    let pf = PixelFormat::rgb888_le();
    stream.write_all(&w.to_be_bytes()).unwrap();
    stream.write_all(&h.to_be_bytes()).unwrap();
    stream.write_all(&pf.encode()).unwrap();
    stream
        .write_all(&(name.len() as u32).to_be_bytes())
        .unwrap();
    stream.write_all(name.as_bytes()).unwrap();
}

fn mock_server(mut stream: TcpStream) {
    // Version
    stream.write_all(b"RFB 003.008\n").unwrap();
    let mut client_ver = [0u8; 12];
    stream.read_exact(&mut client_ver).unwrap();

    // Security: None only
    stream.write_all(&[1, SEC_NONE]).unwrap();
    let mut chosen = [0u8; 1];
    stream.read_exact(&mut chosen).unwrap();
    assert_eq!(chosen[0], SEC_NONE);

    stream.write_all(&SEC_RESULT_OK.to_be_bytes()).unwrap();

    // ClientInit
    let mut shared = [0u8; 1];
    stream.read_exact(&mut shared).unwrap();

    write_server_init(&mut stream, 2, 1, "mock");

    // SetEncodings
    let mut enc_hdr = [0u8; 4];
    stream.read_exact(&mut enc_hdr).unwrap();
    assert_eq!(enc_hdr[0], 2);
    let n = u16::from_be_bytes([enc_hdr[2], enc_hdr[3]]) as usize;
    let mut encs = vec![0u8; n * 4];
    stream.read_exact(&mut encs).unwrap();

    // First FB update request (non-incremental from client handshake)
    let mut req = [0u8; 10];
    stream.read_exact(&mut req).unwrap();
    assert_eq!(req[0], 3);

    // Send one Raw FramebufferUpdate: 2x1 pixels blue
    let pf = PixelFormat::rgb888_le();
    let mut msg = Vec::new();
    msg.push(MSG_FRAMEBUFFER_UPDATE);
    msg.push(0);
    msg.extend_from_slice(&1u16.to_be_bytes());
    // rect
    msg.extend_from_slice(&0u16.to_be_bytes());
    msg.extend_from_slice(&0u16.to_be_bytes());
    msg.extend_from_slice(&2u16.to_be_bytes());
    msg.extend_from_slice(&1u16.to_be_bytes());
    msg.extend_from_slice(&ENC_RAW.to_be_bytes());
    // two pixels B=255
    for _ in 0..2 {
        let mut pix = vec![0u8; pf.bytes_per_pixel()];
        // blue at shift 16
        pix[2] = 255;
        msg.extend_from_slice(&pix);
    }
    stream.write_all(&msg).unwrap();

    // Client may send incremental request then pointer
    let mut buf = [0u8; 64];
    // read incremental FB req
    let _ = stream.read(&mut buf);
    // optional pointer
    let _ = stream.set_read_timeout(Some(Duration::from_millis(200)));
    let _ = stream.read(&mut buf);
}

#[test]
fn mock_peer_handshake_raw_and_pointer() {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let addr = listener.local_addr().unwrap();
    let server = thread::spawn(move || {
        let (stream, _) = listener.accept().unwrap();
        mock_server(stream);
    });

    let stream = TcpStream::connect(addr).unwrap();
    stream
        .set_read_timeout(Some(Duration::from_secs(2)))
        .unwrap();
    let mut session = connect_stream(stream, &Creds::default()).expect("handshake");
    assert_eq!(session.desktop_size(), (2, 1));

    let mut sink = RecSink { damages: 0 };
    session.poll(&mut sink).expect("poll");
    assert!(sink.damages >= 1);

    session
        .send_pointer(PointerEvent {
            x: 1,
            y: 0,
            buttons: 0,
        })
        .unwrap();
    session.close();
    server.join().unwrap();
}

#[test]
#[ignore = "requires local TigerVNC/Xvnc on 127.0.0.1:5900"]
fn live_tigervnc_optional() {
    use helmhost_core::{ConnectTarget, SessionFactory};
    use helmhost_rfb::RfbSessionFactory;
    let factory = RfbSessionFactory::new();
    let _session = factory
        .connect(
            &ConnectTarget {
                host: "127.0.0.1".into(),
                port: 5900,
            },
            &Creds {
                password: Some(String::new()),
            },
        )
        .expect("live connect");
}
