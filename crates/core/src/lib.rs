//! Application core: registry, sessions, focus, protocol traits.
#![forbid(unsafe_code)]

pub mod focus;
pub mod protocol;
pub mod registry;
pub mod session;

pub use focus::InputFocus;
pub use protocol::{
    ConnectTarget, Creds, FrameSink, KeyEvent, PointerEvent, ProtocolId, Rect, RemoteSession,
    SessionFactory, SessionStatus,
};
pub use registry::{ConnectionEntry, ConnectionRegistry};
pub use session::{SessionId, SessionManager};
