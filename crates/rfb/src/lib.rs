//! RFB / VNC protocol engine.
#![forbid(unsafe_code)]

pub mod auth;
pub mod factory;
pub mod fb_cache;
pub mod handshake;
pub mod io;
pub mod messages;
pub mod pixel_format;
pub mod session;
pub mod vencrypt;
pub mod zrle;

pub use factory::{connect_stream, RfbSessionFactory};
pub use pixel_format::PixelFormat;
pub use vencrypt::TlsOptions;
