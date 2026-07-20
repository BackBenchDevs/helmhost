//! In-memory connection registry with optional JSON persistence.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;

/// Saved connection entry (no live socket; no secrets).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConnectionEntry {
    pub id: String,
    pub host: String,
    pub port: u16,
    #[serde(default)]
    pub display_name: Option<String>,
    #[serde(default)]
    pub display_number: Option<u16>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub last_connected_at: Option<i64>,
    #[serde(default)]
    pub thumb_path: Option<String>,
    #[serde(default)]
    pub username: Option<String>,
    #[serde(default)]
    pub prefer_vencrypt: bool,
    #[serde(default)]
    pub accept_invalid_certs: bool,
    #[serde(default)]
    pub view_only: bool,
    #[serde(default)]
    pub notes: Option<String>,
}

impl ConnectionEntry {
    pub fn new(id: impl Into<String>, host: impl Into<String>, port: u16) -> Self {
        Self {
            id: id.into(),
            host: host.into(),
            port,
            display_name: None,
            display_number: None,
            tags: Vec::new(),
            last_connected_at: None,
            thumb_path: None,
            username: None,
            prefer_vencrypt: false,
            accept_invalid_certs: false,
            view_only: false,
            notes: None,
        }
    }
}

/// In-memory map of connection entries.
#[derive(Debug, Default, Serialize, Deserialize)]
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

    /// Merge another registry by id (upsert).
    pub fn merge_from(&mut self, other: ConnectionRegistry) {
        for e in other.entries.into_values() {
            self.upsert(e);
        }
    }

    pub fn to_json(&self) -> Result<String, String> {
        serde_json::to_string_pretty(self).map_err(|e| e.to_string())
    }

    pub fn from_json(s: &str) -> Result<Self, String> {
        serde_json::from_str(s).map_err(|e| e.to_string())
    }

    pub fn save_to_path(&self, path: &Path) -> Result<(), String> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        std::fs::write(path, self.to_json()?).map_err(|e| e.to_string())
    }

    pub fn load_from_path(path: &Path) -> Result<Self, String> {
        let data = std::fs::read_to_string(path).map_err(|e| e.to_string())?;
        Self::from_json(&data)
    }
}

/// Classic VNC display `:N` → TCP port `5900 + N`.
pub fn port_from_display(display: u16) -> u16 {
    5900u16.saturating_add(display)
}

/// Best-effort inverse when port is in the common 5900+ range.
pub fn display_from_port(port: u16) -> Option<u16> {
    if (5900..=5999).contains(&port) {
        Some(port - 5900)
    } else {
        None
    }
}
