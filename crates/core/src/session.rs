//! Live session identifiers and placeholder session table (F01).

use std::collections::HashMap;

/// Opaque id for a live remote session.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct SessionId(pub u64);

/// Tracks live session ids. Protocol engines attach in P3.
#[derive(Debug, Default)]
pub struct SessionManager {
    next_id: u64,
    live: HashMap<SessionId, ()>,
}

impl SessionManager {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn alloc_id(&mut self) -> SessionId {
        self.next_id = self.next_id.saturating_add(1);
        SessionId(self.next_id)
    }

    pub fn insert_placeholder(&mut self, id: SessionId) {
        self.live.insert(id, ());
    }

    pub fn remove(&mut self, id: SessionId) -> bool {
        self.live.remove(&id).is_some()
    }

    pub fn contains(&self, id: SessionId) -> bool {
        self.live.contains_key(&id)
    }

    pub fn len(&self) -> usize {
        self.live.len()
    }

    pub fn is_empty(&self) -> bool {
        self.live.is_empty()
    }
}
