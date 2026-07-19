//! Protocol-agnostic session traits (F04). RFB implements these in P3.

use crate::session::SessionId;

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

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SessionStatus {
    Ok,
    Closed,
    Error(String),
}

/// Receives framebuffer updates from a [`RemoteSession`].
pub trait FrameSink: Send {
    fn on_desktop_resize(&mut self, w: u32, h: u32);
    fn on_damage(&mut self, rect: Rect, rgba: &[u8]);
}

/// Live remote desktop session — protocol-agnostic.
pub trait RemoteSession: Send {
    fn session_id(&self) -> SessionId;
    fn desktop_size(&self) -> (u32, u32);
    fn send_pointer(&mut self, ev: PointerEvent) -> Result<(), String>;
    fn send_key(&mut self, ev: KeyEvent) -> Result<(), String>;
    fn poll(&mut self, sink: &mut dyn FrameSink) -> Result<SessionStatus, String>;
    fn close(&mut self);
}

/// Creates [`RemoteSession`] instances for one protocol.
pub trait SessionFactory: Send + Sync {
    fn protocol(&self) -> ProtocolId;
    fn connect(
        &self,
        target: &ConnectTarget,
        creds: &Creds,
    ) -> Result<Box<dyn RemoteSession>, String>;
}
