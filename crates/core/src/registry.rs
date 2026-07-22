//! In-memory connection registry with optional JSON persistence.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;

/// Shared defaults for a domain/subdomain group of hosts.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConnectionProfile {
    pub id: String,
    pub name: String,
    /// DNS suffix for the group, e.g. `lab.internal`.
    #[serde(default)]
    pub domain: String,
    #[serde(default)]
    pub notes: Option<String>,
    #[serde(default)]
    pub prefer_vencrypt: bool,
    #[serde(default)]
    pub accept_invalid_certs: bool,
    #[serde(default)]
    pub view_only: bool,
    #[serde(default)]
    pub default_username: Option<String>,
    #[serde(default)]
    pub default_display: Option<u16>,
    /// Legacy fields ignored on write; used only while migrating old JSON.
    #[serde(default, skip_serializing)]
    pub dns_search: Vec<String>,
    #[serde(default, skip_serializing)]
    pub cidrs: Vec<String>,
    #[serde(default, skip_serializing)]
    pub dns_servers: Vec<String>,
}

impl ConnectionProfile {
    pub fn new(id: impl Into<String>, name: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            name: name.into(),
            domain: String::new(),
            notes: None,
            prefer_vencrypt: false,
            accept_invalid_certs: false,
            view_only: false,
            default_username: None,
            default_display: None,
            dns_search: Vec::new(),
            cidrs: Vec::new(),
            dns_servers: Vec::new(),
        }
    }

    /// Normalize domain and migrate legacy `dns_search[0]` when domain empty.
    pub fn normalize(&mut self) {
        self.domain = normalize_domain(&self.domain);
        if self.domain.is_empty() {
            if let Some(first) = self.dns_search.first() {
                self.domain = normalize_domain(first);
            }
        }
        self.dns_search.clear();
        self.cidrs.clear();
        self.dns_servers.clear();
    }
}

/// Effective settings after profile inheritance.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResolvedConnectionSettings {
    pub prefer_vencrypt: bool,
    pub accept_invalid_certs: bool,
    pub view_only: bool,
    pub username: Option<String>,
    pub profile_id: Option<String>,
    pub domain: Option<String>,
    /// Hostname used for TCP connect (may be FQDN).
    pub connect_host: String,
    pub display_number: Option<u16>,
}

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
    /// Explicit profile. `None` = auto via domain suffix (or no profile).
    #[serde(default)]
    pub profile_id: Option<String>,
    /// When true, do not auto-match domain even if `profile_id` is None.
    #[serde(default)]
    pub profile_none: bool,
    /// `lan` | `balanced` | `low` (default balanced).
    #[serde(default = "default_bandwidth_preset")]
    pub bandwidth_preset: String,
    /// Optional Tight JPEG quality 0–9.
    #[serde(default)]
    pub quality_level: Option<i32>,
    /// Optional Tight zlib compress 0–9.
    #[serde(default)]
    pub compress_level: Option<i32>,
}

fn default_bandwidth_preset() -> String {
    "balanced".into()
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
            profile_id: None,
            profile_none: false,
            bandwidth_preset: default_bandwidth_preset(),
            quality_level: None,
            compress_level: None,
        }
    }
}

/// In-memory map of connection entries and profiles.
#[derive(Debug, Default, Serialize, Deserialize)]
pub struct ConnectionRegistry {
    entries: HashMap<String, ConnectionEntry>,
    #[serde(default)]
    profiles: HashMap<String, ConnectionProfile>,
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

    pub fn upsert_profile(&mut self, mut profile: ConnectionProfile) {
        profile.normalize();
        self.profiles.insert(profile.id.clone(), profile);
    }

    pub fn get_profile(&self, id: &str) -> Option<&ConnectionProfile> {
        self.profiles.get(id)
    }

    pub fn remove_profile(&mut self, id: &str) -> bool {
        self.profiles.remove(id).is_some()
    }

    pub fn list_profiles(&self) -> impl Iterator<Item = &ConnectionProfile> {
        self.profiles.values()
    }

    pub fn profile_count(&self) -> usize {
        self.profiles.len()
    }

    /// Merge another registry by id (upsert entries + profiles).
    pub fn merge_from(&mut self, other: ConnectionRegistry) {
        for e in other.entries.into_values() {
            self.upsert(e);
        }
        for p in other.profiles.into_values() {
            self.upsert_profile(p);
        }
    }

    /// Find profile whose domain is a suffix of [host] (longest domain wins).
    pub fn find_profile_by_domain(&self, host: &str) -> Option<&ConnectionProfile> {
        let host = host.trim().to_ascii_lowercase();
        let mut best: Option<&ConnectionProfile> = None;
        for p in self.profiles.values() {
            let domain = normalize_domain(&p.domain);
            if domain.is_empty() {
                continue;
            }
            if host_matches_domain(&host, &domain) {
                match best {
                    None => best = Some(p),
                    Some(cur) => {
                        if domain.len() > normalize_domain(&cur.domain).len() {
                            best = Some(p);
                        }
                    }
                }
            }
        }
        best
    }

    /// Resolve effective settings: host override → explicit profile → domain match.
    pub fn resolve(&self, entry: &ConnectionEntry) -> ResolvedConnectionSettings {
        let profile = if entry.profile_none {
            None
        } else if let Some(id) = entry.profile_id.as_ref().filter(|s| !s.is_empty()) {
            self.profiles.get(id.as_str())
        } else {
            self.find_profile_by_domain(&entry.host)
        };

        let domain = profile
            .map(|p| normalize_domain(&p.domain))
            .filter(|d| !d.is_empty());

        let connect_host = match &domain {
            Some(d) => qualify_host(&entry.host, d),
            None => entry.host.trim().to_string(),
        };

        let prefer_vencrypt =
            entry.prefer_vencrypt || profile.map(|p| p.prefer_vencrypt).unwrap_or(false);
        let accept_invalid_certs =
            entry.accept_invalid_certs || profile.map(|p| p.accept_invalid_certs).unwrap_or(false);
        let view_only = entry.view_only || profile.map(|p| p.view_only).unwrap_or(false);

        let username = entry
            .username
            .clone()
            .filter(|s| !s.is_empty())
            .or_else(|| {
                profile
                    .and_then(|p| p.default_username.clone())
                    .filter(|s| !s.is_empty())
            });

        let display_number = entry
            .display_number
            .or_else(|| profile.and_then(|p| p.default_display));

        ResolvedConnectionSettings {
            prefer_vencrypt,
            accept_invalid_certs,
            view_only,
            username,
            profile_id: profile.map(|p| p.id.clone()),
            domain,
            connect_host,
            display_number,
        }
    }

    pub fn to_json(&self) -> Result<String, String> {
        serde_json::to_string_pretty(self).map_err(|e| e.to_string())
    }

    pub fn from_json(s: &str) -> Result<Self, String> {
        let mut reg: Self = serde_json::from_str(s).map_err(|e| e.to_string())?;
        // Migrate legacy profile fields into domain.
        let profiles: Vec<_> = reg.profiles.values().cloned().collect();
        for mut p in profiles {
            p.normalize();
            reg.profiles.insert(p.id.clone(), p);
        }
        Ok(reg)
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

pub fn normalize_domain(domain: &str) -> String {
    domain
        .trim()
        .trim_start_matches('.')
        .trim_end_matches('.')
        .to_ascii_lowercase()
}

/// True if [host] equals [domain] or ends with `.{domain}`.
pub fn host_matches_domain(host: &str, domain: &str) -> bool {
    let host = host.trim().to_ascii_lowercase();
    let domain = normalize_domain(domain);
    if domain.is_empty() || host.is_empty() {
        return false;
    }
    host == domain || host.ends_with(&format!(".{domain}"))
}

/// Strip `.{domain}` suffix to a short hostname when present.
pub fn short_host(host: &str, domain: &str) -> String {
    let host = host.trim();
    let domain = normalize_domain(domain);
    if domain.is_empty() {
        return host.to_string();
    }
    let lower = host.to_ascii_lowercase();
    let suffix = format!(".{domain}");
    if lower.ends_with(&suffix) {
        return host[..host.len() - suffix.len()].to_string();
    }
    if lower == domain {
        return String::new();
    }
    host.to_string()
}

/// Qualify a short hostname with domain. Leaves FQDNs / IPs unchanged when already dotted
/// unless they already end with the domain (normalize) or are short (no dots).
pub fn qualify_host(host: &str, domain: &str) -> String {
    let h = host.trim();
    let domain = normalize_domain(domain);
    if h.is_empty() {
        return h.to_string();
    }
    if domain.is_empty() {
        return h.to_string();
    }
    // Already under this domain → return as-is (normalized casing on domain only via short+qualify)
    if host_matches_domain(h, &domain) {
        let short = short_host(h, &domain);
        if short.is_empty() {
            return domain;
        }
        return format!("{short}.{domain}");
    }
    // Short name (no dots) or bare label → append domain
    if !h.contains('.') {
        return format!("{h}.{domain}");
    }
    // Other FQDN / IP — leave unchanged
    h.to_string()
}
