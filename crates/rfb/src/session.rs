//! Live RFB session over a synchronous stream.

use crate::handshake::{
    encode_client_init, encode_client_version, parse_security_result, parse_security_types,
    parse_server_init, parse_version, pick_security, read_exact, vnc_auth_exchange, write_all,
    SEC_NONE, SEC_VNC_AUTH,
};
use crate::messages::{
    apply_raw_rect, encode_fb_update_request, encode_key_event, encode_pointer_event,
    encode_set_encodings, parse_fb_update_header, parse_rect_header, ENC_RAW,
};
use crate::pixel_format::PixelFormat;
use helmhost_core::{
    Creds, FrameSink, KeyEvent, PointerEvent, RemoteSession, SessionId, SessionStatus,
};
use std::io::{Read, Write};
use std::net::TcpStream;
use std::time::Duration;

pub struct RfbSession<S> {
    id: SessionId,
    stream: S,
    width: u16,
    height: u16,
    pixel_format: PixelFormat,
    closed: bool,
    pending_request: bool,
}

impl RfbSession<TcpStream> {
    pub fn connect_tcp(
        id: SessionId,
        host: &str,
        port: u16,
        creds: &Creds,
    ) -> Result<Self, String> {
        let addr = format!("{host}:{port}");
        let stream = TcpStream::connect(&addr).map_err(|e| format!("connect {addr}: {e}"))?;
        stream.set_read_timeout(Some(Duration::from_secs(30))).ok();
        stream.set_write_timeout(Some(Duration::from_secs(30))).ok();
        Self::handshake(id, stream, creds)
    }
}

impl<S: Read + Write> RfbSession<S> {
    pub fn handshake(id: SessionId, mut stream: S, creds: &Creds) -> Result<Self, String> {
        let ver = read_exact(&mut stream, 12)?;
        let _ = parse_version(&ver)?;
        write_all(&mut stream, &encode_client_version())?;

        let nbuf = read_exact(&mut stream, 1)?;
        let n = nbuf[0] as usize;
        let types = if n == 0 {
            return Err("server sent zero security types".into());
        } else {
            let rest = read_exact(&mut stream, n)?;
            let mut full = Vec::with_capacity(1 + n);
            full.push(nbuf[0]);
            full.extend_from_slice(&rest);
            parse_security_types(&full)?
        };

        let have_pw = creds.password.as_ref().is_some_and(|p| !p.is_empty());
        let sec = pick_security(&types, have_pw)?;
        write_all(&mut stream, &[sec])?;

        match sec {
            SEC_NONE => {}
            SEC_VNC_AUTH => {
                let pw = creds
                    .password
                    .as_deref()
                    .ok_or_else(|| "password required for VNC Auth".to_string())?;
                vnc_auth_exchange(&mut stream, pw)?;
            }
            other => return Err(format!("unsupported security {other}")),
        }

        // SecurityResult (for 3.8 with None and VNC Auth)
        let result = read_exact(&mut stream, 4)?;
        parse_security_result(&result)?;

        write_all(&mut stream, &encode_client_init(true))?;
        // ServerInit: 24 + name
        let head = read_exact(&mut stream, 24)?;
        let name_len = u32::from_be_bytes([head[20], head[21], head[22], head[23]]) as usize;
        let name_bytes = read_exact(&mut stream, name_len)?;
        let mut init_buf = head;
        init_buf.extend_from_slice(&name_bytes);
        let init = parse_server_init(&init_buf)?;

        write_all(&mut stream, &encode_set_encodings(&[ENC_RAW]))?;

        let mut session = Self {
            id,
            stream,
            width: init.width,
            height: init.height,
            pixel_format: init.pixel_format,
            closed: false,
            pending_request: false,
        };
        session.request_update(false)?;
        Ok(session)
    }

    fn request_update(&mut self, incremental: bool) -> Result<(), String> {
        let msg = encode_fb_update_request(incremental, 0, 0, self.width, self.height);
        write_all(&mut self.stream, &msg)?;
        self.pending_request = true;
        Ok(())
    }

    fn read_one_update(&mut self, sink: &mut dyn FrameSink) -> Result<SessionStatus, String> {
        let hdr = read_exact(&mut self.stream, 4)?;
        let (nrects, _) = parse_fb_update_header(&hdr)?;
        for _ in 0..nrects {
            let rh = read_exact(&mut self.stream, 12)?;
            let (rect, _) = parse_rect_header(&rh)?;
            let bpp = self.pixel_format.bytes_per_pixel();
            let nbytes = bpp * rect.w as usize * rect.h as usize;
            let data = read_exact(&mut self.stream, nbytes)?;
            apply_raw_rect(&self.pixel_format, &rect, &data, sink)?;
        }
        self.pending_request = false;
        self.request_update(true)?;
        Ok(SessionStatus::Ok)
    }
}

impl<S: Read + Write + Send> RemoteSession for RfbSession<S> {
    fn session_id(&self) -> SessionId {
        self.id
    }

    fn desktop_size(&self) -> (u32, u32) {
        (u32::from(self.width), u32::from(self.height))
    }

    fn send_pointer(&mut self, ev: PointerEvent) -> Result<(), String> {
        if self.closed {
            return Err("session closed".into());
        }
        write_all(&mut self.stream, &encode_pointer_event(ev))
    }

    fn send_key(&mut self, ev: KeyEvent) -> Result<(), String> {
        if self.closed {
            return Err("session closed".into());
        }
        write_all(&mut self.stream, &encode_key_event(ev))
    }

    fn poll(&mut self, sink: &mut dyn FrameSink) -> Result<SessionStatus, String> {
        if self.closed {
            return Ok(SessionStatus::Closed);
        }
        match self.read_one_update(sink) {
            Ok(s) => Ok(s),
            Err(e) => {
                // Treat timeout / WouldBlock as Ok idle
                if e.contains("TimedOut") || e.contains("WouldBlock") {
                    Ok(SessionStatus::Ok)
                } else {
                    Err(e)
                }
            }
        }
    }

    fn close(&mut self) {
        self.closed = true;
    }
}
