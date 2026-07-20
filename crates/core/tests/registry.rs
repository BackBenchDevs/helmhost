//! Public-API tests for connection registry (P1-T04).

use helmhost_core::{
    display_from_port, port_from_display, ConnectionEntry, ConnectionRegistry,
};

fn entry(id: &str, host: &str, port: u16) -> ConnectionEntry {
    ConnectionEntry::new(id, host, port)
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
        display_number: Some(0),
        tags: vec!["lab".into()],
        last_connected_at: Some(1),
        thumb_path: Some("thumbs/lab.jpg".into()),
        username: None,
        prefer_vencrypt: false,
        accept_invalid_certs: false,
        view_only: false,
        notes: None,
    });
    assert_eq!(
        reg.get("lab").and_then(|e| e.display_name.as_deref()),
        Some("Lab PC")
    );
    assert_eq!(reg.get("lab").map(|e| e.tags.len()), Some(1));
}

#[test]
fn json_round_trip_persistence() {
    let mut reg = ConnectionRegistry::new();
    let mut e = entry("a", "127.0.0.1", 5900);
    e.tags = vec!["home".into()];
    e.thumb_path = Some("thumbs/a.jpg".into());
    reg.upsert(e);
    let json = reg.to_json().unwrap();
    let loaded = ConnectionRegistry::from_json(&json).unwrap();
    assert_eq!(loaded.get("a").map(|e| e.port), Some(5900));
    assert_eq!(
        loaded.get("a").and_then(|e| e.thumb_path.as_deref()),
        Some("thumbs/a.jpg")
    );
}

#[test]
fn merge_from_upserts_by_id() {
    let mut a = ConnectionRegistry::new();
    a.upsert(entry("x", "h", 5900));
    let mut b = ConnectionRegistry::new();
    let mut e = entry("x", "h2", 5901);
    e.display_name = Some("Renamed".into());
    b.upsert(e);
    b.upsert(entry("y", "h3", 5902));
    a.merge_from(b);
    assert_eq!(a.len(), 2);
    assert_eq!(a.get("x").map(|e| e.port), Some(5901));
    assert_eq!(
        a.get("x").and_then(|e| e.display_name.as_deref()),
        Some("Renamed")
    );
}

#[test]
fn extended_fields_json_round_trip() {
    let mut reg = ConnectionRegistry::new();
    reg.upsert(ConnectionEntry {
        id: "srv".into(),
        host: "10.0.0.2".into(),
        port: 5901,
        display_name: Some("Server".into()),
        display_number: Some(1),
        tags: vec!["prod".into()],
        last_connected_at: Some(100),
        thumb_path: Some("thumbs/srv.jpg".into()),
        username: Some("alice".into()),
        prefer_vencrypt: false,
        accept_invalid_certs: false,
        view_only: false,
        notes: Some("lab box".into()),
    });
    let loaded = ConnectionRegistry::from_json(&reg.to_json().unwrap()).unwrap();
    let e = loaded.get("srv").unwrap();
    assert_eq!(e.username.as_deref(), Some("alice"));
    assert!(!e.prefer_vencrypt);
    assert_eq!(e.notes.as_deref(), Some("lab box"));
}

#[test]
fn display_port_helpers() {
    assert_eq!(port_from_display(0), 5900);
    assert_eq!(port_from_display(1), 5901);
    assert_eq!(display_from_port(5901), Some(1));
    assert_eq!(display_from_port(6000), None);
}
