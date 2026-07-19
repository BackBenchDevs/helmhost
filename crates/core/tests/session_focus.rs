//! Public-API tests for session manager and input focus (P1-T03).

use helmhost_core::{InputFocus, SessionId, SessionManager};

#[test]
fn alloc_ids_are_unique_and_increasing() {
    let mut mgr = SessionManager::new();
    let a = mgr.alloc_id();
    let b = mgr.alloc_id();
    assert_ne!(a, b);
    assert_eq!(a, SessionId(1));
    assert_eq!(b, SessionId(2));
}

#[test]
fn insert_remove_len() {
    let mut mgr = SessionManager::new();
    assert!(mgr.is_empty());
    let id = mgr.alloc_id();
    mgr.insert_placeholder(id);
    assert!(mgr.contains(id));
    assert_eq!(mgr.len(), 1);
    assert!(mgr.remove(id));
    assert!(!mgr.contains(id));
    assert!(mgr.is_empty());
    assert!(!mgr.remove(id));
}

#[test]
fn grab_replaces_previous_session() {
    let mut focus = InputFocus::Released;
    let a = SessionId(1);
    let b = SessionId(2);
    focus.grab(a);
    assert_eq!(focus.grabbed_id(), Some(a));
    focus.grab(b);
    assert_eq!(focus.grabbed_id(), Some(b));
    assert!(focus.is_grabbed());
    focus.release();
    assert_eq!(focus, InputFocus::Released);
    assert!(!focus.is_grabbed());
}

#[test]
fn release_when_already_released_is_idempotent() {
    let mut focus = InputFocus::Released;
    focus.release();
    assert_eq!(focus, InputFocus::Released);
}

#[test]
fn contains_false_for_never_inserted_id() {
    let mgr = SessionManager::new();
    assert!(!mgr.contains(SessionId(99)));
}
