//! RFB / VNC protocol engine.
#![forbid(unsafe_code)]

pub mod auth;
pub mod encoding;
pub mod factory;
pub mod fb_cache;
pub mod handshake;
pub mod io;
pub mod messages;
pub mod pixel_format;
pub mod session;
pub mod tight;
pub mod vencrypt;
pub mod zrle;

pub use encoding::{
    compress_level_encoding, encoding_name, encodings_with_quality_compress, preferred_encodings,
    preferred_encodings_for, quality_level_encoding, BandwidthPreset, RectAction,
    ENC_CONTINUOUS_UPDATES, ENC_TIGHT,
};
pub use factory::{connect_stream, RfbSessionFactory};
pub use pixel_format::PixelFormat;
pub use tight::{decode_tight_body, read_compact, TightStream};
pub use vencrypt::TlsOptions;
