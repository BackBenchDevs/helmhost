//! In-memory connection registry (F03). Persistence lands in P4.

use std::collections::HashMap;

/// Saved connection entry (no live socket).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConnectionEntry {
    pub id: String,
    pub host: String,
    pub port: u16,
    pub display_name: Option<String>,
}

/// In-memory map of connection entries.
#[derive(Debug, Default)]
pub struct ConnectionRegistry {
    entries: HashMap<String, ConnectionEntry>,
}

impl ConnectionRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn upsert(&mut self, entry: ConnectionEntry) {
        self.entries.insert(entry.id.clone(), entry);
    }

    pub fn get(&self, id: &str) -> Option<&ConnectionEntry> {
        self.entries.get(id)
    }

    pub fn remove(&mut self, id: &str) -> bool {
        self.entries.remove(id).is_some()
    }

    pub fn list(&self) -> impl Iterator<Item = &ConnectionEntry> {
        self.entries.values()
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }
}
