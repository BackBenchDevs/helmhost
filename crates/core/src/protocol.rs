//! Protocol-agnostic async session API (command / event queues).

use crate::session::SessionId;
use std::future::Future;
use std::pin::Pin;
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
    pub password: Option<String>,
}

impl std::fmt::Debug for Creds {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Creds")
            .field("password", &self.password.as_ref().map(|_| "***"))
            .finish()
    }
}

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
    Close,
}

/// Session → app events (reader/decode tasks produce these).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SessionEvent {
    DesktopResize { w: u32, h: u32 },
    Damage { rect: Rect, rgba: Vec<u8> },
    Bell,
    Clipboard(String),
    Disconnected,
    Error(String),
}

/// Default bound for per-session command / event queues.
pub const DEFAULT_QUEUE_CAPACITY: usize = 64;

/// Handle returned after a successful async connect.
pub struct SessionHandle {
    pub id: SessionId,
    pub width: u32,
    pub height: u32,
    pub events: mpsc::Receiver<SessionEvent>,
    pub commands: mpsc::Sender<SessionCommand>,
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
