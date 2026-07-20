//! Protocol-agnostic async session API (command / event queues).

use crate::fb_cache::FramebufferCache;
use crate::session::SessionId;
use std::future::Future;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use tokio::sync::mpsc;

/// Boxed async future used by [`SessionFactory::connect`].
pub type BoxFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

/// Identifies a remote-desktop protocol (e.g. RFB).
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct ProtocolId(pub &'static str);

impl ProtocolId {
    pub const RFB: Self = Self("rfb");
}

/// Host and port to connect to.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConnectTarget {
    pub host: String,
    pub port: u16,
}

/// Credentials for a connect attempt. Never log `password`.
#[derive(Clone, Default)]
pub struct Creds {
    pub username: Option<String>,
    pub password: Option<String>,
}

impl std::fmt::Debug for Creds {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Creds")
            .field("username", &self.username.as_ref().map(|_| "***"))
            .field("password", &self.password.as_ref().map(|_| "***"))
            .finish()
    }
}

/// Typed connect errors Flutter can map to auth dialogs.
pub const NEED_PASSWORD: &str = "NEED_PASSWORD";
pub const NEED_USERNAME_PASSWORD: &str = "NEED_USERNAME_PASSWORD";


/// Damage / framebuffer rectangle (top-left origin).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Rect {
    pub x: i32,
    pub y: i32,
    pub w: u32,
    pub h: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PointerEvent {
    pub x: i32,
    pub y: i32,
    pub buttons: u8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct KeyEvent {
    pub down: bool,
    pub keysym: u32,
}

/// App → session commands (writer task drains these).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SessionCommand {
    Pointer(PointerEvent),
    Key(KeyEvent),
    CutText(String),
    RequestUpdate { incremental: bool },
    /// TigerVNC RemoteResize: request remote FB = w×h (ExtendedDesktopSize).
    SetDesktopSize { w: u32, h: u32 },
    Close,
}

/// Session → app events (reader/decode tasks produce these).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SessionEvent {
    DesktopResize { w: u32, h: u32 },
    /// Framebuffer region changed; pixels live in [`SessionHandle::framebuffer`].
    FramebufferDirty { rect: Rect },
    Bell,
    Clipboard(String),
    Disconnected,
    Error(String),
}

/// Default bound for per-session command / event queues.
pub const DEFAULT_QUEUE_CAPACITY: usize = 256;

/// Handle returned after a successful async connect.
pub struct SessionHandle {
    pub id: SessionId,
    pub width: u32,
    pub height: u32,
    pub events: mpsc::Receiver<SessionEvent>,
    pub commands: mpsc::Sender<SessionCommand>,
    /// Shared RGBA8 cache; FFI pulls snapshots via `copy_to`.
    pub framebuffer: Arc<Mutex<FramebufferCache>>,
}

impl SessionHandle {
    pub async fn send(&self, cmd: SessionCommand) -> Result<(), String> {
        self.commands
            .send(cmd)
            .await
            .map_err(|_| "session command queue closed".to_string())
    }

    pub async fn close(self) -> Result<(), String> {
        self.send(SessionCommand::Close).await
    }
}

/// Creates async RFB (or other) sessions behind a queue handle.
pub trait SessionFactory: Send + Sync {
    fn protocol(&self) -> ProtocolId;

    fn connect(
        &self,
        target: ConnectTarget,
        creds: Creds,
    ) -> BoxFuture<'_, Result<SessionHandle, String>>;
}
