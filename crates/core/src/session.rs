//! Live session identifiers and async-aware session table.

use crate::protocol::SessionCommand;
use std::collections::HashMap;
use tokio::sync::mpsc;

/// Opaque id for a live remote session.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct SessionId(pub u64);

/// Tracks live sessions by id and their command senders.
#[derive(Debug, Default)]
pub struct SessionManager {
    next_id: u64,
    live: HashMap<SessionId, mpsc::Sender<SessionCommand>>,
}

impl SessionManager {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn alloc_id(&mut self) -> SessionId {
        self.next_id = self.next_id.saturating_add(1);
        SessionId(self.next_id)
    }

    pub fn insert(&mut self, id: SessionId, commands: mpsc::Sender<SessionCommand>) {
        self.live.insert(id, commands);
    }

    /// Legacy placeholder insert (no command channel). Prefer [`Self::insert`].
    pub fn insert_placeholder(&mut self, id: SessionId) {
        let (tx, _rx) = mpsc::channel(1);
        self.live.insert(id, tx);
    }

    pub fn remove(&mut self, id: SessionId) -> bool {
        self.live.remove(&id).is_some()
    }

    pub fn contains(&self, id: SessionId) -> bool {
        self.live.contains_key(&id)
    }

    pub fn commands(&self, id: SessionId) -> Option<&mpsc::Sender<SessionCommand>> {
        self.live.get(&id)
    }

    pub async fn close(&mut self, id: SessionId) -> Result<(), String> {
        let Some(tx) = self.live.get(&id).cloned() else {
            return Err(format!("unknown session {id:?}"));
        };
        tx.send(SessionCommand::Close)
            .await
            .map_err(|_| "session already closed".to_string())?;
        self.live.remove(&id);
        Ok(())
    }

    pub fn len(&self) -> usize {
        self.live.len()
    }

    pub fn is_empty(&self) -> bool {
        self.live.is_empty()
    }
}
