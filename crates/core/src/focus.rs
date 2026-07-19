//! Input focus: at most one Grabbed remote session (F02).

use crate::session::SessionId;

/// Whether remote input is captured for a session.
///
/// Grabbing a new session **replaces** any previous Grabbed target.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum InputFocus {
    #[default]
    Released,
    Grabbed(SessionId),
}

impl InputFocus {
    /// Grab `id`, replacing any prior Grabbed session.
    pub fn grab(&mut self, id: SessionId) {
        *self = Self::Grabbed(id);
    }

    /// Release focus to the local host.
    pub fn release(&mut self) {
        *self = Self::Released;
    }

    pub fn grabbed_id(&self) -> Option<SessionId> {
        match self {
            Self::Grabbed(id) => Some(*id),
            Self::Released => None,
        }
    }

    pub fn is_grabbed(&self) -> bool {
        matches!(self, Self::Grabbed(_))
    }
}
