//! C ABI for Helmhost Flutter client.
//!
//! Also exposes a Rust `hello()` used by unit tests (FRB-ready surface).
#![allow(clippy::missing_safety_doc)]

use base64::{engine::general_purpose::STANDARD as B64, Engine};
use helmhost_core::{
    ConnectTarget, ConnectionEntry, ConnectionRegistry, Creds, InputFocus, KeyEvent, PointerEvent,
    SessionCommand, SessionEvent, SessionHandle, SessionId, SessionManager,
};
use helmhost_rfb::RfbSessionFactory;
use once_cell::sync::Lazy;
use serde::Serialize;
use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::PathBuf;
use std::sync::Mutex;
use tokio::runtime::Runtime;

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

#[derive(Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum FfiEvent {
    DesktopResize { w: u32, h: u32 },
    Damage {
        x: i32,
        y: i32,
        w: u32,
        h: u32,
        rgba_b64: String,
    },
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
        Some(SessionEvent::Damage { rect, rgba }) => FfiEvent::Damage {
            x: rect.x,
            y: rect.y,
            w: rect.w,
            h: rect.h,
            rgba_b64: B64.encode(&rgba),
        },
        Some(SessionEvent::Bell) => FfiEvent::Bell,
        Some(SessionEvent::Clipboard(text)) => FfiEvent::Clipboard { text },
        Some(SessionEvent::Disconnected) => FfiEvent::Disconnected,
        Some(SessionEvent::Error(message)) => FfiEvent::Error { message },
    };
    serde_json::to_string(&mapped).unwrap_or_else(|_| r#"{"type":"error","message":"serialize"}"#.into())
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
#[no_mangle]
pub extern "C" fn hh_string_free(s: *mut c_char) {
    if s.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(s));
    }
}

#[no_mangle]
pub extern "C" fn hh_hello() -> *mut c_char {
    ok_cstr(hello())
}

#[no_mangle]
pub extern "C" fn hh_connect(
    host: *const c_char,
    port: u16,
    password: *const c_char,
) -> *mut c_char {
    let host = match cstr_to_string(host) {
        Ok(h) => h,
        Err(e) => return err_cstr(e),
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

    let result = RT.block_on(async {
        let mut state = STATE.lock().map_err(|_| "lock".to_string())?;
        use helmhost_core::SessionFactory;
        let handle = state
            .factory
            .connect(
                ConnectTarget {
                    host: host.clone(),
                    port,
                },
                Creds { password },
            )
            .await?;
        let id = handle.id.0;
        state.manager.insert(handle.id, handle.commands.clone());
        state.sessions.insert(id, handle);
        // upsert registry entry
        let entry_id = format!("{host}:{port}");
        state.registry.upsert(ConnectionEntry {
            id: entry_id,
            host,
            port,
            display_name: None,
        });
        if let Some(path) = state.registry_path.clone() {
            let _ = state.registry.save_to_path(&path);
        }
        Ok::<_, String>(id)
    });

    match result {
        Ok(id) => ok_cstr(id.to_string()),
        Err(e) => err_cstr(e),
    }
}

#[no_mangle]
pub extern "C" fn hh_poll_event(session_id: u64) -> *mut c_char {
    let result: Result<String, String> = RT.block_on(async {
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
    });
    match result {
        Ok(s) => ok_cstr(s),
        Err(e) => err_cstr(e),
    }
}

#[no_mangle]
pub extern "C" fn hh_send_pointer(session_id: u64, x: i32, y: i32, buttons: u8) -> *mut c_char {
    send_cmd(
        session_id,
        SessionCommand::Pointer(PointerEvent { x, y, buttons }),
    )
}

#[no_mangle]
pub extern "C" fn hh_send_key(session_id: u64, down: u8, keysym: u32) -> *mut c_char {
    send_cmd(
        session_id,
        SessionCommand::Key(KeyEvent {
            down: down != 0,
            keysym,
        }),
    )
}

#[no_mangle]
pub extern "C" fn hh_close(session_id: u64) -> *mut c_char {
    let result = RT.block_on(async {
        let mut state = STATE.lock().map_err(|_| "lock".to_string())?;
        if let Some(handle) = state.sessions.remove(&session_id) {
            state.manager.remove(SessionId(session_id));
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
        let state = STATE.lock().map_err(|_| "lock".to_string())?;
        let Some(handle) = state.sessions.get(&session_id) else {
            return Err("unknown session".to_string());
        };
        handle.send(cmd).await
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
                if let Ok(reg) = ConnectionRegistry::load_from_path(&path) {
                    s.registry = reg;
                }
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
        cstr_to_string(display_name).ok()
    };
    match STATE.lock() {
        Ok(mut s) => {
            s.registry.upsert(ConnectionEntry {
                id,
                host,
                port,
                display_name,
            });
            if let Some(path) = s.registry_path.clone() {
                let _ = s.registry.save_to_path(&path);
            }
            ok_cstr("ok")
        }
        Err(_) => err_cstr("lock"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hello_is_helmhost() {
        assert_eq!(hello(), "helmhost");
    }
}
