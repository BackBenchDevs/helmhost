//! RFB / VNC protocol engine.
#![forbid(unsafe_code)]

pub mod auth;
pub mod factory;
pub mod handshake;
pub mod messages;
pub mod pixel_format;
pub mod session;

pub use factory::{connect_stream, RfbSessionFactory};
pub use pixel_format::PixelFormat;
pub use session::RfbSession;
