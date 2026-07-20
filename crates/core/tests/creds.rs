//! Creds must never leak secrets via Debug.

use helmhost_core::Creds;

#[test]
fn debug_redacts_password() {
    let creds = Creds {
        username: Some("alice".into()),
        password: Some("s3cret-password".into()),
    };
    let rendered = format!("{creds:?}");
    assert!(
        !rendered.contains("s3cret-password"),
        "Debug leaked password: {rendered}"
    );
    assert!(!rendered.contains("alice"), "Debug leaked username: {rendered}");
    assert!(rendered.contains("***"));
}

#[test]
fn debug_none_password() {
    let creds = Creds::default();
    let rendered = format!("{creds:?}");
    assert!(rendered.contains("None") || rendered.contains("password"));
    assert!(!rendered.contains("***"));
}
