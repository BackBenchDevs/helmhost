//! Application core: registry, sessions, focus, async protocol traits.
#![forbid(unsafe_code)]

pub mod fb_cache;
pub mod focus;
pub mod protocol;
pub mod registry;
pub mod runtime;
pub mod session;

pub use fb_cache::FramebufferCache;
pub use focus::InputFocus;
pub use protocol::{
    BoxFuture, ConnectTarget, Creds, DEFAULT_QUEUE_CAPACITY, KeyEvent, PointerEvent, ProtocolId,
    Rect, SessionCommand, SessionEvent, SessionFactory, SessionHandle, NEED_PASSWORD,
    NEED_USERNAME_PASSWORD,
};
pub use registry::{
    display_from_port, port_from_display, ConnectionEntry, ConnectionRegistry,
};
pub use runtime::HelmRuntime;
pub use session::{SessionId, SessionManager};
