//! Public-API tests for connection registry (P1-T04).

use helmhost_core::{ConnectionEntry, ConnectionRegistry};

fn entry(id: &str, host: &str, port: u16) -> ConnectionEntry {
    ConnectionEntry {
        id: id.into(),
        host: host.into(),
        port,
        display_name: None,
    }
}

#[test]
fn upsert_get_and_overwrite() {
    let mut reg = ConnectionRegistry::new();
    assert!(reg.is_empty());
    reg.upsert(entry("a", "1.2.3.4", 5900));
    assert_eq!(reg.get("a").map(|e| e.port), Some(5900));
    reg.upsert(entry("a", "1.2.3.4", 5901));
    assert_eq!(reg.get("a").map(|e| e.port), Some(5901));
    assert_eq!(reg.len(), 1);
}

#[test]
fn get_missing_is_none() {
    let reg = ConnectionRegistry::new();
    assert!(reg.get("missing").is_none());
}

#[test]
fn remove_and_list() {
    let mut reg = ConnectionRegistry::new();
    reg.upsert(entry("a", "h1", 5900));
    reg.upsert(entry("b", "h2", 5901));
    assert_eq!(reg.list().count(), 2);
    assert!(reg.remove("a"));
    assert!(!reg.remove("a"));
    assert_eq!(reg.list().count(), 1);
    assert!(reg.get("b").is_some());
}

#[test]
fn display_name_round_trip() {
    let mut reg = ConnectionRegistry::new();
    reg.upsert(ConnectionEntry {
        id: "lab".into(),
        host: "10.0.0.1".into(),
        port: 5900,
        display_name: Some("Lab PC".into()),
    });
    assert_eq!(
        reg.get("lab").and_then(|e| e.display_name.as_deref()),
        Some("Lab PC")
    );
}
