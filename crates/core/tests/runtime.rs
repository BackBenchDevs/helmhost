//! Shared multi-thread runtime unit test.

use helmhost_core::HelmRuntime;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

#[test]
fn helm_runtime_spawns_tasks() {
    let rt = HelmRuntime::new().expect("runtime");
    let counter = Arc::new(AtomicUsize::new(0));
    let c = Arc::clone(&counter);
    let h = rt.spawn(async move {
        c.fetch_add(1, Ordering::SeqCst);
    });
    rt.handle().block_on(h).unwrap();
    assert_eq!(counter.load(Ordering::SeqCst), 1);
}
