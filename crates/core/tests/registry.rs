//! Public-API tests for connection registry + domain profiles.

use helmhost_core::{
    display_from_port, host_matches_domain, normalize_domain, port_from_display, qualify_host,
    short_host, ConnectionEntry, ConnectionProfile, ConnectionRegistry,
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
        profile_id: None,
        profile_none: false,
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
        host: "pc01".into(),
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
        profile_id: Some("p1".into()),
        profile_none: false,
    });
    let loaded = ConnectionRegistry::from_json(&reg.to_json().unwrap()).unwrap();
    let e = loaded.get("srv").unwrap();
    assert_eq!(e.username.as_deref(), Some("alice"));
    assert_eq!(e.profile_id.as_deref(), Some("p1"));
}

#[test]
fn display_port_helpers() {
    assert_eq!(port_from_display(0), 5900);
    assert_eq!(port_from_display(1), 5901);
    assert_eq!(display_from_port(5901), Some(1));
    assert_eq!(display_from_port(6000), None);
}

#[test]
fn missing_profiles_key_loads_empty() {
    let json = r#"{"entries":{}}"#;
    let reg = ConnectionRegistry::from_json(json).unwrap();
    assert_eq!(reg.profile_count(), 0);
}

#[test]
fn profile_crud_and_domain_persist() {
    let mut reg = ConnectionRegistry::new();
    let mut p = ConnectionProfile::new("lab", "Lab");
    p.domain = "lab.internal".into();
    p.prefer_vencrypt = true;
    p.default_username = Some("labuser".into());
    p.default_display = Some(1);
    reg.upsert_profile(p);
    let mut loaded = ConnectionRegistry::from_json(&reg.to_json().unwrap()).unwrap();
    let p = loaded.get_profile("lab").unwrap();
    assert_eq!(p.domain, "lab.internal");
    assert_eq!(p.default_display, Some(1));
    assert!(loaded.remove_profile("lab"));
}

#[test]
fn migrate_legacy_dns_search_to_domain() {
    let json = r#"{
      "entries": {},
      "profiles": {
        "lab": {
          "id": "lab",
          "name": "Lab",
          "dns_search": ["lab.internal"],
          "cidrs": ["10.0.1.0/24"],
          "dns_servers": ["10.0.1.53"]
        }
      }
    }"#;
    let reg = ConnectionRegistry::from_json(json).unwrap();
    assert_eq!(
        reg.get_profile("lab").map(|p| p.domain.as_str()),
        Some("lab.internal")
    );
    let exported = reg.to_json().unwrap();
    assert!(!exported.contains("dns_servers"));
    assert!(!exported.contains("cidrs"));
}

#[test]
fn qualify_and_short_host() {
    assert_eq!(qualify_host("pc01", "lab.internal"), "pc01.lab.internal");
    assert_eq!(
        qualify_host("pc01.lab.internal", "lab.internal"),
        "pc01.lab.internal"
    );
    assert_eq!(qualify_host("10.0.0.1", "lab.internal"), "10.0.0.1");
    assert_eq!(short_host("pc01.lab.internal", "lab.internal"), "pc01");
    assert!(host_matches_domain("pc01.lab.internal", "lab.internal"));
    assert_eq!(normalize_domain(".Lab.Internal."), "lab.internal");
}

#[test]
fn resolve_domain_inheritance() {
    let mut reg = ConnectionRegistry::new();
    let mut p = ConnectionProfile::new("lab", "Lab");
    p.domain = "lab.internal".into();
    p.prefer_vencrypt = true;
    p.default_username = Some("from-domain".into());
    p.default_display = Some(2);
    reg.upsert_profile(p);

    let mut explicit = ConnectionProfile::new("ex", "Explicit");
    explicit.domain = "other.internal".into();
    explicit.default_username = Some("from-explicit".into());
    reg.upsert_profile(explicit);

    // Domain suffix auto-match on FQDN
    let e = entry("a", "pc01.lab.internal", 5900);
    let r = reg.resolve(&e);
    assert_eq!(r.username.as_deref(), Some("from-domain"));
    assert_eq!(r.connect_host, "pc01.lab.internal");
    assert_eq!(r.profile_id.as_deref(), Some("lab"));
    assert_eq!(r.display_number, Some(2));

    // Explicit profile + short host → qualify
    let mut e2 = entry("b", "gw", 5900);
    e2.profile_id = Some("lab".into());
    let r2 = reg.resolve(&e2);
    assert_eq!(r2.connect_host, "gw.lab.internal");
    assert_eq!(r2.username.as_deref(), Some("from-domain"));

    // Host username overrides
    let mut e3 = entry("c", "gw", 5900);
    e3.profile_id = Some("lab".into());
    e3.username = Some("host-user".into());
    e3.display_number = Some(0);
    let r3 = reg.resolve(&e3);
    assert_eq!(r3.username.as_deref(), Some("host-user"));
    assert_eq!(r3.display_number, Some(0));

    // profile_none skips domain match
    let mut e4 = entry("d", "pc01.lab.internal", 5900);
    e4.profile_none = true;
    let r4 = reg.resolve(&e4);
    assert!(r4.profile_id.is_none());
    assert_eq!(r4.connect_host, "pc01.lab.internal");
}

#[test]
fn merge_keeps_profiles() {
    let mut a = ConnectionRegistry::new();
    let mut p1 = ConnectionProfile::new("p1", "One");
    p1.domain = "one.example".into();
    a.upsert_profile(p1);
    let mut b = ConnectionRegistry::new();
    let mut p2 = ConnectionProfile::new("p2", "Two");
    p2.domain = "two.example".into();
    b.upsert_profile(p2);
    let mut e = entry("h", "host", 5900);
    e.profile_id = Some("p2".into());
    b.upsert(e);
    a.merge_from(b);
    assert_eq!(a.profile_count(), 2);
    assert_eq!(a.get("h").and_then(|e| e.profile_id.as_deref()), Some("p2"));
}
