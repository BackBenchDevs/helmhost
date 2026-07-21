//! Async RFB session: handshake then reader + writer tasks on command/event queues.

use crate::encoding::{rect_fits_framebuffer, encoding_name, RectAction};
use crate::handshake::{
    finish_client_server_init, handshake_security_and_init, parse_security_result,
    vnc_auth_exchange, ServerInit, SEC_NONE, SEC_VENCRYPT, SEC_VNC_AUTH,
};
use crate::io::{read_exact, write_all};
use crate::messages::{
    decode_raw_rect, encode_client_cut_text, encode_fb_update_request, encode_key_event,
    encode_pointer_event, encode_set_desktop_size, encode_set_encodings, encode_set_pixel_format,
    parse_copyrect_src, parse_fb_update_header, parse_rect_header, parse_server_cut_text,
    preferred_encodings, ENC_COPYRECT, ENC_DESKTOP_SIZE, ENC_EXTENDED_DESKTOP_SIZE, ENC_LAST_RECT,
    ENC_RAW, ENC_ZRLE, MSG_BELL, MSG_FRAMEBUFFER_UPDATE, MSG_SERVER_CUT_TEXT, MSG_SET_COLOUR_MAP,
};
use crate::pixel_format::PixelFormat;
use crate::vencrypt::{
    negotiate_vencrypt_subtype, wrap_tcp_tls, TlsOptions, VENCRYPT_TLSNONE, VENCRYPT_TLSVNC,
};
use crate::zrle::{decode_zrle_with, ZrleStream};
use helmhost_core::{
    Creds, FramebufferCache, Rect, SessionCommand, SessionEvent, SessionHandle, SessionId,
    DEFAULT_QUEUE_CAPACITY,
};
use std::sync::{Arc, Mutex as StdMutex};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::sync::{mpsc, Mutex};

struct SharedDesktop {
    width: u16,
    height: u16,
    pixel_format: PixelFormat,
    cache: Arc<StdMutex<FramebufferCache>>,
}

impl SharedDesktop {
    fn new(width: u16, height: u16, pf: PixelFormat) -> Self {
        Self {
            width,
            height,
            pixel_format: pf,
            cache: Arc::new(StdMutex::new(FramebufferCache::new(
                u32::from(width),
                u32::from(height),
            ))),
        }
    }
}

/// Connect TCP, handshake, spawn reader/writer tasks, return queue handle.
pub async fn connect_tcp(
    id: SessionId,
    host: &str,
    port: u16,
    creds: Creds,
    tls: TlsOptions,
    prefer_vencrypt: bool,
) -> Result<SessionHandle, String> {
    let addr = format!("{host}:{port}");
    let stream = TcpStream::connect(&addr)
        .await
        .map_err(|e| format!("connect {addr}: {e}"))?;
    match connect_stream(id, stream, host, creds.clone(), tls.clone(), prefer_vencrypt).await {
        Ok(handle) => Ok(handle),
        Err(e) if prefer_vencrypt && is_vencrypt_fallback_error(&e) => {
            let stream = TcpStream::connect(&addr)
                .await
                .map_err(|re| format!("connect {addr} (fallback): {re}"))?;
            connect_stream(id, stream, host, creds, tls, false)
                .await
                .map_err(|e2| format!("{e}; classic fallback failed: {e2}"))
        }
        Err(e) => Err(e),
    }
}

fn is_vencrypt_fallback_error(err: &str) -> bool {
    err.contains("zero subtypes") || err.contains("no supported subtype")
}

/// Handshake over an existing TCP stream (tests / tunnels).
pub async fn connect_stream(
    id: SessionId,
    mut stream: TcpStream,
    host: &str,
    creds: Creds,
    tls: TlsOptions,
    prefer_vencrypt: bool,
) -> Result<SessionHandle, String> {
    let (init, vencrypt) =
        handshake_security_and_init(&mut stream, &creds, prefer_vencrypt).await?;

    if vencrypt == Some(SEC_VENCRYPT) {
        return connect_vencrypt(id, stream, host, creds, tls).await;
    }

    spawn_session_tasks(id, stream, init).await
}

async fn connect_vencrypt(
    id: SessionId,
    mut stream: TcpStream,
    host: &str,
    creds: Creds,
    tls: TlsOptions,
) -> Result<SessionHandle, String> {
    let have_pw = creds.password.as_ref().is_some_and(|p| !p.is_empty());
    let subtype = negotiate_vencrypt_subtype(&mut stream, have_pw).await?;
    let mut tls_stream = wrap_tcp_tls(stream, host, &tls).await?;

    match subtype {
        VENCRYPT_TLSNONE => {}
        VENCRYPT_TLSVNC => {
            let pw = creds
                .password
                .as_deref()
                .ok_or_else(|| helmhost_core::NEED_PASSWORD.to_string())?;
            vnc_auth_exchange(&mut tls_stream, pw).await?;
            let result = read_exact(&mut tls_stream, 4).await?;
            parse_security_result(&result)?;
        }
        other if other == u32::from(SEC_NONE) => {}
        other if other == u32::from(SEC_VNC_AUTH) => {
            let pw = creds
                .password
                .as_deref()
                .ok_or_else(|| "password required for VNC Auth".to_string())?;
            vnc_auth_exchange(&mut tls_stream, pw).await?;
            let result = read_exact(&mut tls_stream, 4).await?;
            parse_security_result(&result)?;
        }
        other => return Err(format!("unsupported VeNCrypt subtype {other}")),
    }

    let init = finish_client_server_init(&mut tls_stream).await?;
    spawn_session_tasks(id, tls_stream, init).await
}

/// Test helper: any AsyncRead+AsyncWrite+Send stream (e.g. duplex / accepted socket).
pub async fn connect_any<S>(
    id: SessionId,
    mut stream: S,
    creds: &Creds,
) -> Result<SessionHandle, String>
where
    S: AsyncRead + AsyncWrite + Unpin + Send + 'static,
{
    let (init, vencrypt) = handshake_security_and_init(&mut stream, creds, false).await?;
    if vencrypt.is_some() {
        return Err("VeNCrypt requires TCP path".into());
    }
    spawn_session_tasks(id, stream, init).await
}

async fn spawn_session_tasks<S>(
    id: SessionId,
    mut stream: S,
    init: ServerInit,
) -> Result<SessionHandle, String>
where
    S: AsyncRead + AsyncWrite + Unpin + Send + 'static,
{
    write_all(
        &mut stream,
        &encode_set_pixel_format(&PixelFormat::rgb888_le()),
    )
    .await?;
    write_all(&mut stream, &encode_set_encodings(&preferred_encodings())).await?;
    tracing::debug!(
        width = init.width,
        height = init.height,
        encodings = ?preferred_encodings(),
        "rfb encodings advertised"
    );

    let mut desktop = SharedDesktop::new(init.width, init.height, init.pixel_format);
    desktop.pixel_format = PixelFormat::rgb888_le();

    let req = encode_fb_update_request(false, 0, 0, desktop.width, desktop.height);
    write_all(&mut stream, &req).await?;

    let (cmd_tx, cmd_rx) = mpsc::channel::<SessionCommand>(DEFAULT_QUEUE_CAPACITY);
    let (ev_tx, ev_rx) = mpsc::channel::<SessionEvent>(DEFAULT_QUEUE_CAPACITY);

    let _ = ev_tx
        .send(SessionEvent::DesktopResize {
            w: u32::from(desktop.width),
            h: u32::from(desktop.height),
        })
        .await;

    let shared = Arc::new(Mutex::new(desktop));
    let framebuffer = {
        let g = shared.lock().await;
        Arc::clone(&g.cache)
    };
    let (mut rd, mut wr) = tokio::io::split(stream);

    let writer_state = Arc::clone(&shared);
    tokio::spawn(async move {
        writer_loop(&mut wr, cmd_rx, writer_state).await;
    });

    let reader_state = Arc::clone(&shared);
    let cmd_tx_reader = cmd_tx.clone();
    tokio::spawn(async move {
        if let Err(e) = reader_loop(&mut rd, ev_tx.clone(), cmd_tx_reader, reader_state).await {
            let _ = send_event(&ev_tx, SessionEvent::Error(e)).await;
        }
        let _ = send_event(&ev_tx, SessionEvent::Disconnected).await;
    });

    Ok(SessionHandle {
        id,
        width: u32::from(init.width),
        height: u32::from(init.height),
        events: ev_rx,
        commands: cmd_tx,
        framebuffer,
    })
}

async fn send_event(tx: &mpsc::Sender<SessionEvent>, ev: SessionEvent) {
    // Always await: try_send was dropping framebuffer damage under load → black UI.
    let _ = tx.send(ev).await;
}

async fn writer_loop<W: AsyncWrite + Unpin>(
    wr: &mut W,
    mut cmd_rx: mpsc::Receiver<SessionCommand>,
    state: Arc<Mutex<SharedDesktop>>,
) {
    while let Some(cmd) = cmd_rx.recv().await {
        let result = match cmd {
            SessionCommand::Close => {
                let _ = wr.shutdown().await;
                break;
            }
            SessionCommand::Pointer(ev) => write_all(wr, &encode_pointer_event(ev)).await,
            SessionCommand::Key(ev) => write_all(wr, &encode_key_event(ev)).await,
            SessionCommand::CutText(text) => write_all(wr, &encode_client_cut_text(&text)).await,
            SessionCommand::RequestUpdate { incremental } => {
                let g = state.lock().await;
                let msg = encode_fb_update_request(incremental, 0, 0, g.width, g.height);
                drop(g);
                write_all(wr, &msg).await
            }
            SessionCommand::SetDesktopSize { w, h } => {
                let width = u16::try_from(w).unwrap_or(u16::MAX);
                let height = u16::try_from(h).unwrap_or(u16::MAX);
                if width == 0 || height == 0 {
                    Ok(())
                } else {
                    write_all(wr, &encode_set_desktop_size(width, height)).await
                }
            }
        };
        if result.is_err() {
            break;
        }
    }
}

async fn reader_loop<R: AsyncRead + Unpin>(
    rd: &mut R,
    ev_tx: mpsc::Sender<SessionEvent>,
    cmd_tx: mpsc::Sender<SessionCommand>,
    state: Arc<Mutex<SharedDesktop>>,
) -> Result<(), String> {
    // RFC 6143: one zlib stream for all ZRLE rectangles on this connection.
    let mut zrle = ZrleStream::new();
    loop {
        let mut typ = [0u8; 1];
        match rd.read_exact(&mut typ).await {
            Ok(_) => {}
            Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => return Ok(()),
            Err(e) => return Err(e.to_string()),
        }

        match typ[0] {
            MSG_FRAMEBUFFER_UPDATE => {
                let rest = read_exact(rd, 3).await?;
                let mut hdr = vec![MSG_FRAMEBUFFER_UPDATE];
                hdr.extend_from_slice(&rest);
                let (nrects, _) = parse_fb_update_header(&hdr)?;
                // TigerVNC: LastRect ends the update early (nRects may be 0xFFFF).
                let mut remaining = nrects;
                let mut dirty: Option<Rect> = None;
                while remaining > 0 {
                    remaining -= 1;
                    match handle_rect(rd, &ev_tx, &state, &mut zrle).await? {
                        (RectAction::Continue, Some(r)) => {
                            dirty = Some(match dirty {
                                Some(d) => d.union(r),
                                None => r,
                            });
                        }
                        (RectAction::Continue, None) => {}
                        (RectAction::EndFramebufferUpdate, _) => break,
                    }
                }
                if let Some(rect) = dirty {
                    send_event(&ev_tx, SessionEvent::FramebufferDirty { rect }).await;
                }
                let _ = cmd_tx
                    .send(SessionCommand::RequestUpdate { incremental: true })
                    .await;
            }
            MSG_SET_COLOUR_MAP => {
                let _pad = read_exact(rd, 1).await?;
                let _first = read_exact(rd, 2).await?;
                let n = read_exact(rd, 2).await?;
                let ncolors = u16::from_be_bytes([n[0], n[1]]) as usize;
                let _ = read_exact(rd, ncolors * 6).await?;
            }
            MSG_BELL => {
                send_event(&ev_tx, SessionEvent::Bell).await;
            }
            MSG_SERVER_CUT_TEXT => {
                let _pad = read_exact(rd, 3).await?;
                let lenb = read_exact(rd, 4).await?;
                let len = u32::from_be_bytes([lenb[0], lenb[1], lenb[2], lenb[3]]) as usize;
                let payload = read_exact(rd, len).await?;
                let text = parse_server_cut_text(&payload).unwrap_or_default();
                send_event(&ev_tx, SessionEvent::Clipboard(text)).await;
            }
            other => {
                // Log and stop — unknown types have no safe skip length
                return Err(format!("unknown server message type {other}"));
            }
        }
    }
}

async fn handle_rect<R: AsyncRead + Unpin>(
    rd: &mut R,
    ev_tx: &mpsc::Sender<SessionEvent>,
    state: &Arc<Mutex<SharedDesktop>>,
    zrle: &mut ZrleStream,
) -> Result<(RectAction, Option<Rect>), String> {
    let rh = read_exact(rd, 12).await?;
    let (hdr, _) = parse_rect_header(&rh)?;

    {
        let g = state.lock().await;
        rect_fits_framebuffer(g.width, g.height, &hdr)?;
    }

    match hdr.encoding {
        ENC_RAW => {
            let bpp = {
                let g = state.lock().await;
                g.pixel_format.bytes_per_pixel()
            };
            let nbytes = bpp * hdr.w as usize * hdr.h as usize;
            let data = read_exact(rd, nbytes).await?;
            let g = state.lock().await;
            let (rect, rgba) = decode_raw_rect(&g.pixel_format, &hdr, &data)?;
            g.cache
                .lock()
                .map_err(|_| "fb cache lock".to_string())?
                .put_damage(rect, &rgba)?;
            drop(g);
            Ok((RectAction::Continue, Some(rect)))
        }
        ENC_COPYRECT => {
            let src = read_exact(rd, 4).await?;
            let (sx, sy) = parse_copyrect_src(&src)?;
            let rect = Rect {
                x: i32::from(hdr.x),
                y: i32::from(hdr.y),
                w: u32::from(hdr.w),
                h: u32::from(hdr.h),
            };
            let g = state.lock().await;
            g.cache
                .lock()
                .map_err(|_| "fb cache lock".to_string())?
                .copy_rect(rect, i32::from(sx), i32::from(sy))?;
            drop(g);
            Ok((RectAction::Continue, Some(rect)))
        }
        ENC_ZRLE => {
            let lenb = read_exact(rd, 4).await?;
            let zlen = u32::from_be_bytes([lenb[0], lenb[1], lenb[2], lenb[3]]) as usize;
            let zdata = read_exact(rd, zlen).await?;
            let mut framed = lenb;
            framed.extend_from_slice(&zdata);
            // Zero-area: still consume zlib length + payload to keep stream aligned.
            if hdr.w == 0 || hdr.h == 0 {
                let pf = {
                    let g = state.lock().await;
                    g.pixel_format
                };
                decode_zrle_with(zrle, &pf, 0, 0, &framed)
                    .map_err(|e| format!("zrle decode failed: {e}"))?;
                return Ok((RectAction::Continue, None));
            }
            let g = state.lock().await;
            match decode_zrle_with(
                zrle,
                &g.pixel_format,
                u32::from(hdr.w),
                u32::from(hdr.h),
                &framed,
            ) {
                Ok(rgba) => {
                    let rect = Rect {
                        x: i32::from(hdr.x),
                        y: i32::from(hdr.y),
                        w: u32::from(hdr.w),
                        h: u32::from(hdr.h),
                    };
                    g.cache
                        .lock()
                        .map_err(|_| "fb cache lock".to_string())?
                        .put_damage(rect, &rgba)?;
                    drop(g);
                    Ok((RectAction::Continue, Some(rect)))
                }
                Err(e) => {
                    drop(g);
                    Err(format!("zrle decode failed: {e}"))
                }
            }
        }
        ENC_DESKTOP_SIZE => {
            let mut g = state.lock().await;
            g.width = hdr.w;
            g.height = hdr.h;
            g.cache
                .lock()
                .map_err(|_| "fb cache lock".to_string())?
                .resize(u32::from(hdr.w), u32::from(hdr.h));
            let w = u32::from(hdr.w);
            let h = u32::from(hdr.h);
            drop(g);
            send_event(ev_tx, SessionEvent::DesktopResize { w, h }).await;
            Ok((RectAction::Continue, None))
        }
        ENC_EXTENDED_DESKTOP_SIZE => {
            // Payload: number-of-screens (u8) + pad3 + screens×16.
            // Rect x = reason, y = result (TigerVNC); w/h = new size.
            let n_pad = read_exact(rd, 4).await?;
            let n_screens = n_pad[0] as usize;
            let _ = read_exact(rd, n_screens * 16).await?;
            let reason = hdr.x;
            let result = hdr.y;
            // reasonClient == 1: only apply size when result == 0 (success).
            const REASON_CLIENT: u16 = 1;
            if reason == REASON_CLIENT && result != 0 {
                return Ok((RectAction::Continue, None));
            }
            let mut g = state.lock().await;
            g.width = hdr.w;
            g.height = hdr.h;
            g.cache
                .lock()
                .map_err(|_| "fb cache lock".to_string())?
                .resize(u32::from(hdr.w), u32::from(hdr.h));
            let w = u32::from(hdr.w);
            let h = u32::from(hdr.h);
            drop(g);
            send_event(ev_tx, SessionEvent::DesktopResize { w, h }).await;
            Ok((RectAction::Continue, None))
        }
        ENC_LAST_RECT => Ok((RectAction::EndFramebufferUpdate, None)),
        other => {
            if hdr.w == 0 || hdr.h == 0 {
                // Zero-area unknown encoding: no payload to skip
                Ok((RectAction::Continue, None))
            } else {
                Err(format!(
                    "unknown encoding {other} ({})",
                    encoding_name(other)
                ))
            }
        }
    }
}
