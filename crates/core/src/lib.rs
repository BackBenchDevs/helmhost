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
    BoxFuture, ConnectTarget, Creds, KeyEvent, PointerEvent, ProtocolId, Rect, SessionCommand,
    SessionEvent, SessionFactory, SessionHandle, DEFAULT_QUEUE_CAPACITY, NEED_PASSWORD,
    NEED_USERNAME_PASSWORD,
};
pub use registry::{
    display_from_port, host_matches_domain, normalize_domain, port_from_display, qualify_host,
    short_host, ConnectionEntry, ConnectionProfile, ConnectionRegistry, ResolvedConnectionSettings,
};
pub use runtime::HelmRuntime;
pub use session::{SessionId, SessionManager};
