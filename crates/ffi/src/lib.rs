//! C ABI for Helmhost Flutter client.
//!
//! Also exposes a Rust `hello()` used by unit tests (FRB-ready surface).
#![allow(clippy::missing_safety_doc)]

use helmhost_core::{
    ConnectionEntry, ConnectionProfile, ConnectionRegistry, Creds, InputFocus, KeyEvent,
    PointerEvent, SessionCommand, SessionEvent, SessionHandle, SessionId, SessionManager,
};
use helmhost_rfb::encodings_with_quality_compress;
use helmhost_rfb::session::connect_tcp;
use helmhost_rfb::RfbSessionFactory;
use helmhost_rfb::TlsOptions;
use once_cell::sync::Lazy;
use serde::Serialize;
use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::path::PathBuf;
use std::sync::{Mutex, Once};
use tokio::runtime::Runtime;
use tracing_subscriber::EnvFilter;

static LOG_INIT: Once = Once::new();

fn init_logging() {
    LOG_INIT.call_once(|| {
        // Quiet by default; set HELMHOST_LOG=info|debug for connect chatter.
        let filter = EnvFilter::try_from_env("HELMHOST_LOG")
            .or_else(|_| EnvFilter::try_from_default_env())
            .unwrap_or_else(|_| EnvFilter::new("warn"));
        let _ = tracing_subscriber::fmt()
            .with_env_filter(filter)
            .with_target(true)
            .try_init();
        tracing::debug!("helmhost-ffi logging initialized");
    });
}

static RT: Lazy<Runtime> = Lazy::new(|| {
    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .thread_name("helmhost-ffi")
        .build()
        .expect("tokio runtime")
});

struct AppState {
    factory: RfbSessionFactory,
    sessions: HashMap<u64, SessionHandle>,
    manager: SessionManager,
    focus: InputFocus,
    registry: ConnectionRegistry,
    registry_path: Option<PathBuf>,
}

impl AppState {
    fn new() -> Self {
        Self {
            factory: RfbSessionFactory::new(),
            sessions: HashMap::new(),
            manager: SessionManager::new(),
            focus: InputFocus::Released,
            registry: ConnectionRegistry::new(),
            registry_path: None,
        }
    }
}

static STATE: Lazy<Mutex<AppState>> = Lazy::new(|| Mutex::new(AppState::new()));

/// FRB-ready hello (also covered by unit tests).
pub fn hello() -> String {
    "helmhost".to_string()
}

/// Workspace / crate version for the Rust core (FFI + RFB stack).
pub fn core_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

#[derive(Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum FfiEvent {
    DesktopResize { w: u32, h: u32 },
    FramebufferDirty { x: i32, y: i32, w: u32, h: u32 },
    Bell,
    Clipboard { text: String },
    Disconnected,
    Error { message: String },
    None,
}

fn encode_event(ev: Option<SessionEvent>) -> String {
    let mapped = match ev {
        None => FfiEvent::None,
        Some(SessionEvent::DesktopResize { w, h }) => FfiEvent::DesktopResize { w, h },
        Some(SessionEvent::FramebufferDirty { rect }) => FfiEvent::FramebufferDirty {
            x: rect.x,
            y: rect.y,
            w: rect.w,
            h: rect.h,
        },
        Some(SessionEvent::Bell) => FfiEvent::Bell,
        Some(SessionEvent::Clipboard(text)) => FfiEvent::Clipboard { text },
        Some(SessionEvent::Disconnected) => FfiEvent::Disconnected,
        Some(SessionEvent::Error(message)) => FfiEvent::Error { message },
    };
    serde_json::to_string(&mapped)
        .unwrap_or_else(|_| r#"{"type":"error","message":"serialize"}"#.into())
}

fn cstr_to_string(p: *const c_char) -> Result<String, String> {
    if p.is_null() {
        return Err("null string".into());
    }
    unsafe { CStr::from_ptr(p) }
        .to_str()
        .map(|s| s.to_string())
        .map_err(|e| e.to_string())
}

fn ok_cstr(s: impl Into<String>) -> *mut c_char {
    CString::new(s.into())
        .unwrap_or_else(|_| CString::new("err").unwrap())
        .into_raw()
}

fn err_cstr(e: impl Into<String>) -> *mut c_char {
    ok_cstr(format!("ERR:{}", e.into()))
}

/// Free a string returned by this library.
///
/// # Safety
/// `s` must be null or a pointer previously returned by this library (via
/// `CString::into_raw`).
#[no_mangle]
pub unsafe extern "C" fn hh_string_free(s: *mut c_char) {
    if s.is_null() {
        return;
    }
    drop(CString::from_raw(s));
}

#[no_mangle]
pub extern "C" fn hh_hello() -> *mut c_char {
    init_logging();
    ok_cstr(hello())
}

#[no_mangle]
pub extern "C" fn hh_core_version() -> *mut c_char {
    init_logging();
    ok_cstr(core_version())
}

#[no_mangle]
pub extern "C" fn hh_connect(
    host: *const c_char,
    port: u16,
    username: *const c_char,
    password: *const c_char,
    prefer_vencrypt: u8,
    accept_invalid_certs: u8,
    bandwidth_preset: u8,
    quality_level: i8,
    compress_level: i8,
) -> *mut c_char {
    init_logging();
    let host = match cstr_to_string(host) {
        Ok(h) => h,
        Err(e) => return err_cstr(e),
    };
    let username = if username.is_null() {
        None
    } else {
        match cstr_to_string(username) {
            Ok(u) if u.is_empty() => None,
            Ok(u) => Some(u),
            Err(e) => return err_cstr(e),
        }
    };
    let password = if password.is_null() {
        None
    } else {
        match cstr_to_string(password) {
            Ok(p) if p.is_empty() => None,
            Ok(p) => Some(p),
            Err(e) => return err_cstr(e),
        }
    };
    let tls = TlsOptions {
        danger_accept_invalid_certs: accept_invalid_certs != 0,
    };
    let prefer = prefer_vencrypt != 0;
    let bandwidth = match bandwidth_preset {
        0 => helmhost_rfb::BandwidthPreset::Lan,
        2 => helmhost_rfb::BandwidthPreset::Low,
        _ => helmhost_rfb::BandwidthPreset::Balanced,
    };
    let quality = if quality_level < 0 {
        None
    } else {
        Some(i32::from(quality_level).clamp(0, 9))
    };
    let compress = if compress_level < 0 {
        None
    } else {
        Some(i32::from(compress_level).clamp(0, 9))
    };
    tracing::debug!(
        %host,
        port,
        prefer_vencrypt = prefer,
        accept_invalid_certs = accept_invalid_certs != 0,
        ?bandwidth,
        ?quality,
        ?compress,
        "hh_connect start"
    );

    let result = RT.block_on(async {
        // Alloc id from global manager (brief lock). Never use a fresh
        // RfbSessionFactory here — that always restarts at id=1 and
        // collapses multi-tab Flutter ValueKeys.
        let id = {
            let mut state = STATE.lock().map_err(|_| "lock".to_string())?;
            state.factory.configure_connect(tls.clone(), prefer);
            state
                .factory
                .configure_bandwidth(bandwidth, quality, compress);
            state.manager.alloc_id()
        };
        let encodings = encodings_with_quality_compress(bandwidth, quality, compress);
        let handle = connect_tcp(
            id,
            &host,
            port,
            Creds { username, password },
            tls,
            prefer,
            &encodings,
        )
        .await?;

        let mut state = STATE.lock().map_err(|_| "lock".to_string())?;
        state.manager.insert(handle.id, handle.commands.clone());
        state.sessions.insert(id.0, handle);
        let entry_id = format!("{host}:{port}");
        let prev = state.registry.get(&entry_id).cloned();
        let mut entry =
            prev.unwrap_or_else(|| ConnectionEntry::new(entry_id.clone(), host.clone(), port));
        entry.host = host.clone();
        entry.port = port;
        entry.last_connected_at = Some(
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs() as i64)
                .unwrap_or(0),
        );
        entry.display_number = helmhost_core::display_from_port(port);
        entry.bandwidth_preset = match bandwidth {
            helmhost_rfb::BandwidthPreset::Lan => "lan".into(),
            helmhost_rfb::BandwidthPreset::Low => "low".into(),
            helmhost_rfb::BandwidthPreset::Balanced => "balanced".into(),
        };
        entry.quality_level = quality;
        entry.compress_level = compress;
        state.registry.upsert(entry);
        if let Some(path) = state.registry_path.clone() {
            let _ = state.registry.save_to_path(&path);
        }
        Ok::<_, String>(id.0)
    });

    match result {
        Ok(id) => {
            tracing::debug!(session_id = id, %host, port, "hh_connect ok");
            ok_cstr(id.to_string())
        }
        Err(e) => {
            tracing::error!(%host, port, error = %e, "hh_connect failed");
            err_cstr(e)
        }
    }
}

#[no_mangle]
pub extern "C" fn hh_poll_event(session_id: u64) -> *mut c_char {
    // Sync try_recv — no block_on on the empty hot path.
    let result: Result<String, String> = (|| {
        let mut state = STATE.lock().map_err(|_| "lock".to_string())?;
        let Some(handle) = state.sessions.get_mut(&session_id) else {
            return Ok(encode_event(Some(SessionEvent::Error(
                "unknown session".into(),
            ))));
        };
        match handle.events.try_recv() {
            Ok(ev) => Ok(encode_event(Some(ev))),
            Err(tokio::sync::mpsc::error::TryRecvError::Empty) => Ok(encode_event(None)),
            Err(tokio::sync::mpsc::error::TryRecvError::Disconnected) => {
                Ok(encode_event(Some(SessionEvent::Disconnected)))
            }
        }
    })();
    match result {
        Ok(s) => ok_cstr(s),
        Err(e) => err_cstr(e),
    }
}

/// Write desktop width/height for `session_id`. Returns 0 on success, -1 on error.
#[no_mangle]
pub unsafe extern "C" fn hh_fb_size(session_id: u64, w: *mut u32, h: *mut u32) -> c_int {
    if w.is_null() || h.is_null() {
        return -1;
    }
    let Ok(state) = STATE.lock() else {
        return -1;
    };
    let Some(handle) = state.sessions.get(&session_id) else {
        return -1;
    };
    let Ok(fb) = handle.framebuffer.lock() else {
        return -1;
    };
    let (fw, fh) = fb.size();
    unsafe {
        *w = fw;
        *h = fh;
    }
    0
}

/// Copy full RGBA8 framebuffer into `out` (`out_len` must be `w*h*4`). Returns 0 or -1.
#[no_mangle]
pub unsafe extern "C" fn hh_fb_copy(session_id: u64, out: *mut u8, out_len: usize) -> c_int {
    if out.is_null() || out_len == 0 {
        return -1;
    }
    let Ok(state) = STATE.lock() else {
        return -1;
    };
    let Some(handle) = state.sessions.get(&session_id) else {
        return -1;
    };
    let Ok(fb) = handle.framebuffer.lock() else {
        return -1;
    };
    let slice = unsafe { std::slice::from_raw_parts_mut(out, out_len) };
    match fb.copy_to(slice) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

/// Copy one RGBA8 rect into `out` (tightly packed `w*h*4`). Returns 0 or -1.
#[no_mangle]
pub unsafe extern "C" fn hh_fb_copy_rect(
    session_id: u64,
    x: i32,
    y: i32,
    w: u32,
    h: u32,
    out: *mut u8,
    out_len: usize,
) -> c_int {
    if out.is_null() || out_len == 0 || w == 0 || h == 0 {
        return -1;
    }
    let Ok(state) = STATE.lock() else {
        return -1;
    };
    let Some(handle) = state.sessions.get(&session_id) else {
        return -1;
    };
    let Ok(fb) = handle.framebuffer.lock() else {
        return -1;
    };
    let slice = unsafe { std::slice::from_raw_parts_mut(out, out_len) };
    match fb.copy_rect_to(helmhost_core::Rect { x, y, w, h }, slice) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

#[no_mangle]
pub extern "C" fn hh_send_pointer(session_id: u64, x: i32, y: i32, buttons: u8) -> c_int {
    send_cmd_try(
        session_id,
        SessionCommand::Pointer(PointerEvent { x, y, buttons }),
    )
}

#[no_mangle]
pub extern "C" fn hh_send_key(session_id: u64, down: u8, keysym: u32) -> c_int {
    send_cmd_try(
        session_id,
        SessionCommand::Key(KeyEvent {
            down: down != 0,
            keysym,
        }),
    )
}

#[no_mangle]
pub extern "C" fn hh_send_clipboard(session_id: u64, text: *const c_char) -> *mut c_char {
    let Ok(s) = cstr_to_string(text) else {
        return err_cstr("bad clipboard text");
    };
    send_cmd(session_id, SessionCommand::CutText(s))
}

/// Request remote desktop resize (TigerVNC RemoteResize / SetDesktopSize).
/// Does not require input focus — matches viewer window resize behavior.
#[no_mangle]
pub extern "C" fn hh_request_desktop_size(session_id: u64, w: u32, h: u32) -> *mut c_char {
    if w == 0 || h == 0 {
        return err_cstr("invalid desktop size");
    }
    send_cmd_unfocused(session_id, SessionCommand::SetDesktopSize { w, h })
}

#[no_mangle]
pub extern "C" fn hh_close(session_id: u64) -> *mut c_char {
    let result = RT.block_on(async {
        let handle = {
            let mut state = STATE.lock().map_err(|_| "lock".to_string())?;
            let handle = state.sessions.remove(&session_id);
            if handle.is_some() {
                state.manager.remove(SessionId(session_id));
            }
            handle
        };
        if let Some(handle) = handle {
            handle.close().await?;
        }
        Ok::<_, String>(())
    });
    match result {
        Ok(()) => ok_cstr("ok"),
        Err(e) => err_cstr(e),
    }
}

fn send_cmd(session_id: u64, cmd: SessionCommand) -> *mut c_char {
    let result = RT.block_on(async {
        let tx = {
            let state = STATE.lock().map_err(|_| "lock".to_string())?;
            if !state.focus.allows(SessionId(session_id)) {
                return Err("focus not grabbed".to_string());
            }
            let Some(handle) = state.sessions.get(&session_id) else {
                return Err("unknown session".to_string());
            };
            handle.commands.clone()
        };
        tx.send(cmd)
            .await
            .map_err(|_| "session command queue closed".to_string())
    });
    match result {
        Ok(()) => ok_cstr("ok"),
        Err(e) => err_cstr(e),
    }
}

/// Hot-path input: try_send, no block_on, no CString. 0 = ok, -1 = error.
fn send_cmd_try(session_id: u64, cmd: SessionCommand) -> c_int {
    let Ok(state) = STATE.lock() else {
        return -1;
    };
    if !state.focus.allows(SessionId(session_id)) {
        return -1;
    }
    let Some(handle) = state.sessions.get(&session_id) else {
        return -1;
    };
    match handle.commands.try_send(cmd) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

fn send_cmd_unfocused(session_id: u64, cmd: SessionCommand) -> *mut c_char {
    let result = RT.block_on(async {
        let tx = {
            let state = STATE.lock().map_err(|_| "lock".to_string())?;
            let Some(handle) = state.sessions.get(&session_id) else {
                return Err("unknown session".to_string());
            };
            handle.commands.clone()
        };
        tx.send(cmd)
            .await
            .map_err(|_| "session command queue closed".to_string())
    });
    match result {
        Ok(()) => ok_cstr("ok"),
        Err(e) => err_cstr(e),
    }
}

#[no_mangle]
pub extern "C" fn hh_focus_grab(session_id: u64) -> *mut c_char {
    match STATE.lock() {
        Ok(mut s) => {
            s.focus.grab(SessionId(session_id));
            ok_cstr("ok")
        }
        Err(_) => err_cstr("lock"),
    }
}

#[no_mangle]
pub extern "C" fn hh_focus_release() -> *mut c_char {
    match STATE.lock() {
        Ok(mut s) => {
            s.focus.release();
            ok_cstr("ok")
        }
        Err(_) => err_cstr("lock"),
    }
}

#[no_mangle]
pub extern "C" fn hh_focus_get() -> *mut c_char {
    match STATE.lock() {
        Ok(s) => match s.focus.grabbed_id() {
            Some(id) => ok_cstr(id.0.to_string()),
            None => ok_cstr("released"),
        },
        Err(_) => err_cstr("lock"),
    }
}

#[no_mangle]
pub extern "C" fn hh_registry_set_path(path: *const c_char) -> *mut c_char {
    let path = match cstr_to_string(path) {
        Ok(p) => PathBuf::from(p),
        Err(e) => return err_cstr(e),
    };
    match STATE.lock() {
        Ok(mut s) => {
            if path.exists() {
                match ConnectionRegistry::load_from_path(&path) {
                    Ok(reg) => s.registry = reg,
                    Err(e) => {
                        eprintln!("[hh_registry_set_path] load failed {}: {e}", path.display());
                    }
                }
            } else {
                eprintln!(
                    "[hh_registry_set_path] missing {} — starting empty",
                    path.display()
                );
            }
            s.registry_path = Some(path);
            ok_cstr("ok")
        }
        Err(_) => err_cstr("lock"),
    }
}

#[no_mangle]
pub extern "C" fn hh_registry_list() -> *mut c_char {
    match STATE.lock() {
        Ok(s) => {
            let list: Vec<&ConnectionEntry> = s.registry.list().collect();
            match serde_json::to_string(&list) {
                Ok(j) => ok_cstr(j),
                Err(e) => err_cstr(e.to_string()),
            }
        }
        Err(_) => err_cstr("lock"),
    }
}

#[no_mangle]
pub extern "C" fn hh_registry_upsert(
    id: *const c_char,
    host: *const c_char,
    port: u16,
    display_name: *const c_char,
) -> *mut c_char {
    let id = match cstr_to_string(id) {
        Ok(v) => v,
        Err(e) => return err_cstr(e),
    };
    let host = match cstr_to_string(host) {
        Ok(v) => v,
        Err(e) => return err_cstr(e),
    };
    let display_name = if display_name.is_null() {
        None
    } else {
        cstr_to_string(display_name).ok().filter(|s| !s.is_empty())
    };
    match STATE.lock() {
        Ok(mut s) => {
            let prev = s.registry.get(&id).cloned();
            let mut entry = ConnectionEntry::new(id, host, port);
            entry.display_name =
                display_name.or_else(|| prev.as_ref().and_then(|p| p.display_name.clone()));
            entry.display_number = helmhost_core::display_from_port(port)
                .or_else(|| prev.as_ref().and_then(|p| p.display_number));
            entry.tags = prev.as_ref().map(|p| p.tags.clone()).unwrap_or_default();
            entry.last_connected_at = prev.as_ref().and_then(|p| p.last_connected_at);
            entry.thumb_path = prev.as_ref().and_then(|p| p.thumb_path.clone());
            entry.username = prev.as_ref().and_then(|p| p.username.clone());
            entry.prefer_vencrypt = prev.as_ref().map(|p| p.prefer_vencrypt).unwrap_or(false);
            entry.accept_invalid_certs = prev
                .as_ref()
                .map(|p| p.accept_invalid_certs)
                .unwrap_or(false);
            entry.view_only = prev.as_ref().map(|p| p.view_only).unwrap_or(false);
            entry.notes = prev.as_ref().and_then(|p| p.notes.clone());
            entry.profile_id = prev.as_ref().and_then(|p| p.profile_id.clone());
            entry.profile_none = prev.as_ref().map(|p| p.profile_none).unwrap_or(false);
            s.registry.upsert(entry);
            if let Some(path) = s.registry_path.clone() {
                let _ = s.registry.save_to_path(&path);
            }
            ok_cstr("ok")
        }
        Err(_) => err_cstr("lock"),
    }
}

/// Upsert a full [`ConnectionEntry`] from JSON (no secrets).
#[no_mangle]
pub extern "C" fn hh_registry_upsert_json(json: *const c_char) -> *mut c_char {
    let raw = match cstr_to_string(json) {
        Ok(v) => v,
        Err(e) => return err_cstr(e),
    };
    let entry: ConnectionEntry = match serde_json::from_str(&raw) {
        Ok(e) => e,
        Err(e) => return err_cstr(e.to_string()),
    };
    match STATE.lock() {
        Ok(mut s) => {
            s.registry.upsert(entry);
            if let Some(path) = s.registry_path.clone() {
                let _ = s.registry.save_to_path(&path);
            }
            ok_cstr("ok")
        }
        Err(_) => err_cstr("lock"),
    }
}

#[no_mangle]
pub extern "C" fn hh_registry_remove(id: *const c_char) -> *mut c_char {
    let id = match cstr_to_string(id) {
        Ok(v) => v,
        Err(e) => return err_cstr(e),
    };
    match STATE.lock() {
        Ok(mut s) => {
            s.registry.remove(&id);
            if let Some(path) = s.registry_path.clone() {
                let _ = s.registry.save_to_path(&path);
            }
            ok_cstr("ok")
        }
        Err(_) => err_cstr("lock"),
    }
}

/// Merge a full registry JSON document (export format).
#[no_mangle]
pub extern "C" fn hh_registry_merge_json(json: *const c_char) -> *mut c_char {
    let raw = match cstr_to_string(json) {
        Ok(v) => v,
        Err(e) => return err_cstr(e),
    };
    let other = match ConnectionRegistry::from_json(&raw) {
        Ok(r) => r,
        Err(e) => return err_cstr(e),
    };
    match STATE.lock() {
        Ok(mut s) => {
            s.registry.merge_from(other);
            if let Some(path) = s.registry_path.clone() {
                let _ = s.registry.save_to_path(&path);
            }
            ok_cstr("ok")
        }
        Err(_) => err_cstr("lock"),
    }
}

/// Export full registry JSON (no secrets stored).
#[no_mangle]
pub extern "C" fn hh_registry_export() -> *mut c_char {
    match STATE.lock() {
        Ok(s) => match s.registry.to_json() {
            Ok(j) => ok_cstr(j),
            Err(e) => err_cstr(e),
        },
        Err(_) => err_cstr("lock"),
    }
}

#[no_mangle]
pub extern "C" fn hh_profile_list() -> *mut c_char {
    match STATE.lock() {
        Ok(s) => {
            let list: Vec<&ConnectionProfile> = s.registry.list_profiles().collect();
            match serde_json::to_string(&list) {
                Ok(j) => ok_cstr(j),
                Err(e) => err_cstr(e.to_string()),
            }
        }
        Err(_) => err_cstr("lock"),
    }
}

#[no_mangle]
pub extern "C" fn hh_profile_upsert_json(json: *const c_char) -> *mut c_char {
    let raw = match cstr_to_string(json) {
        Ok(v) => v,
        Err(e) => return err_cstr(e),
    };
    eprintln!("[hh_profile_upsert_json] raw={raw}");
    let profile: ConnectionProfile = match serde_json::from_str(&raw) {
        Ok(e) => e,
        Err(e) => return err_cstr(e.to_string()),
    };
    eprintln!(
        "[hh_profile_upsert_json] parsed id={} domain={} default_display={:?}",
        profile.id, profile.domain, profile.default_display
    );
    match STATE.lock() {
        Ok(mut s) => {
            s.registry.upsert_profile(profile);
            if let Some(path) = s.registry_path.clone() {
                if let Err(e) = s.registry.save_to_path(&path) {
                    eprintln!("[hh_profile_upsert_json] save error: {e} path={path:?}");
                } else {
                    eprintln!("[hh_profile_upsert_json] saved path={path:?}");
                }
            } else {
                eprintln!("[hh_profile_upsert_json] no registry_path — not persisted");
            }
            ok_cstr("ok")
        }
        Err(_) => err_cstr("lock"),
    }
}

#[no_mangle]
pub extern "C" fn hh_profile_remove(id: *const c_char) -> *mut c_char {
    let id = match cstr_to_string(id) {
        Ok(v) => v,
        Err(e) => return err_cstr(e),
    };
    match STATE.lock() {
        Ok(mut s) => {
            s.registry.remove_profile(&id);
            if let Some(path) = s.registry_path.clone() {
                let _ = s.registry.save_to_path(&path);
            }
            ok_cstr("ok")
        }
        Err(_) => err_cstr("lock"),
    }
}

/// Resolve effective settings for an entry id (JSON of ResolvedConnectionSettings-like map).
#[no_mangle]
pub extern "C" fn hh_registry_resolve(id: *const c_char) -> *mut c_char {
    let id = match cstr_to_string(id) {
        Ok(v) => v,
        Err(e) => return err_cstr(e),
    };
    match STATE.lock() {
        Ok(s) => {
            let Some(entry) = s.registry.get(&id) else {
                return err_cstr("not found");
            };
            let r = s.registry.resolve(entry);
            let v = serde_json::json!({
                "prefer_vencrypt": r.prefer_vencrypt,
                "accept_invalid_certs": r.accept_invalid_certs,
                "view_only": r.view_only,
                "username": r.username,
                "profile_id": r.profile_id,
                "domain": r.domain,
                "connect_host": r.connect_host,
                "display_number": r.display_number,
            });
            match serde_json::to_string(&v) {
                Ok(j) => ok_cstr(j),
                Err(e) => err_cstr(e.to_string()),
            }
        }
        Err(_) => err_cstr("lock"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use helmhost_core::SessionId;
    use std::ffi::CString;

    fn take_cstr(p: *mut c_char) -> String {
        assert!(!p.is_null());
        let s = unsafe { CStr::from_ptr(p) }.to_string_lossy().into_owned();
        unsafe {
            hh_string_free(p);
        }
        s
    }

    #[test]
    fn hello_is_helmhost() {
        assert_eq!(hello(), "helmhost");
    }

    #[test]
    fn core_version_is_semver() {
        let v = core_version();
        assert!(
            v.split('.').count() >= 3,
            "expected semver-like core version, got {v}"
        );
    }

    #[test]
    fn focus_gate_matches_allows() {
        let mut focus = InputFocus::Released;
        assert!(!focus.allows(SessionId(7)));
        focus.grab(SessionId(7));
        assert!(focus.allows(SessionId(7)));
        assert!(!focus.allows(SessionId(8)));
    }

    /// Regression: hh_connect must alloc from global STATE.manager, not a
    /// fresh RfbSessionFactory (which always restarts at 1).
    #[test]
    fn global_manager_allocates_distinct_session_ids() {
        let (a, b) = {
            let mut state = STATE.lock().expect("lock");
            let a = state.manager.alloc_id();
            let b = state.manager.alloc_id();
            (a, b)
        };
        assert_ne!(a, b, "two allocs must not collide (Flutter tab keys)");
        assert_eq!(a.0 + 1, b.0);
    }

    #[test]
    fn registry_set_path_upsert_json_list_remove_round_trip() {
        let path = std::env::temp_dir().join(format!(
            "helmhost-ffi-registry-{}-{}.json",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let _ = std::fs::remove_file(&path);
        let path_c = CString::new(path.to_str().unwrap()).unwrap();
        let set = take_cstr(hh_registry_set_path(path_c.as_ptr()));
        assert_eq!(set, "ok");

        let json = r#"{"id":"lab:5901","host":"lab","port":5901,"display_name":"Lab"}"#;
        let json_c = CString::new(json).unwrap();
        let up = take_cstr(hh_registry_upsert_json(json_c.as_ptr()));
        assert_eq!(up, "ok");

        let list = take_cstr(hh_registry_list());
        assert!(!list.starts_with("ERR:"), "{list}");
        assert!(list.contains("lab:5901"), "{list}");
        assert!(list.contains("Lab"), "{list}");

        let id_c = CString::new("lab:5901").unwrap();
        let rm = take_cstr(hh_registry_remove(id_c.as_ptr()));
        assert_eq!(rm, "ok");

        let list2 = take_cstr(hh_registry_list());
        assert!(!list2.contains("lab:5901"), "{list2}");
        assert!(path.exists());
        let _ = std::fs::remove_file(&path);
    }
}
