//! Application core: registry, sessions, focus, async protocol traits.
#![forbid(unsafe_code)]

pub mod focus;
pub mod protocol;
pub mod registry;
pub mod runtime;
pub mod session;

pub use focus::InputFocus;
pub use protocol::{
    BoxFuture, ConnectTarget, Creds, DEFAULT_QUEUE_CAPACITY, KeyEvent, PointerEvent, ProtocolId,
    Rect, SessionCommand, SessionEvent, SessionFactory, SessionHandle,
};
pub use registry::{ConnectionEntry, ConnectionRegistry};
pub use runtime::HelmRuntime;
pub use session::{SessionId, SessionManager};
