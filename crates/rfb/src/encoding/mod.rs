//! RFB rectangle encodings — constants, bounds checks, update control.
//!
//! Facade: callers import from `helmhost_rfb::encoding` (or via `messages` re-exports).

mod bounds;
mod constants;

pub use bounds::rect_fits_framebuffer;
pub use constants::{
    encoding_name, preferred_encodings, ENC_COPYRECT, ENC_CURSOR, ENC_DESKTOP_SIZE,
    ENC_EXTENDED_DESKTOP_SIZE, ENC_HEXTILE, ENC_JPEG, ENC_LAST_RECT, ENC_RAW, ENC_RRE,
    ENC_TIGHT, ENC_TRLE, ENC_XCURSOR, ENC_ZRLE,
};

/// How to continue after handling one framebuffer rectangle.
///
/// Mirrors TigerVNC `CMsgReader`: LastRect forces the update to end early
/// even if `nRects` claimed more rectangles.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RectAction {
    Continue,
    EndFramebufferUpdate,
}
