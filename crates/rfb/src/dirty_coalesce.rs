//! Non-blocking `FramebufferDirty` delivery with pending rect union under backpressure.
//!
//! Pixels always live in the FB cache. This only coalesces **notifications** so the
//! RFB reader never blocks on a full event queue (which stalled decode/input).

use helmhost_core::{Rect, SessionEvent};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use tokio::sync::mpsc;
use tokio::sync::mpsc::error::TrySendError;

/// Coalesces dirty rects when the event channel is full; never drops coverage.
#[derive(Clone, Default)]
pub struct DirtyCoalescer {
    pending: Arc<Mutex<Option<Rect>>>,
    flushing: Arc<AtomicBool>,
}

impl DirtyCoalescer {
    pub fn new() -> Self {
        Self::default()
    }

    /// Push dirty coverage. Non-blocking for the caller (reader task).
    pub fn send_dirty(&self, tx: &mpsc::Sender<SessionEvent>, rect: Rect) {
        {
            let mut g = self.pending.lock().unwrap_or_else(|e| e.into_inner());
            *g = Some(match g.take() {
                Some(p) => p.union(rect),
                None => rect,
            });
        }
        self.try_flush(tx);
    }

    fn try_flush(&self, tx: &mpsc::Sender<SessionEvent>) {
        loop {
            let Some(rect) = self.take_pending() else {
                return;
            };
            match tx.try_send(SessionEvent::FramebufferDirty { rect }) {
                Ok(()) => continue,
                Err(TrySendError::Full(ev)) => {
                    self.put_back_dirty(ev);
                    self.spawn_flush_when_ready(tx.clone());
                    return;
                }
                Err(TrySendError::Closed(_)) => return,
            }
        }
    }

    fn has_pending(&self) -> bool {
        self.pending
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .is_some()
    }

    fn take_pending(&self) -> Option<Rect> {
        self.pending
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .take()
    }

    fn put_back_dirty(&self, ev: SessionEvent) {
        let SessionEvent::FramebufferDirty { rect } = ev else {
            return;
        };
        let mut g = self.pending.lock().unwrap_or_else(|e| e.into_inner());
        *g = Some(match g.take() {
            Some(p) => p.union(rect),
            None => rect,
        });
    }

    /// When the channel was full, wait for a slot without blocking the reader.
    fn spawn_flush_when_ready(&self, tx: mpsc::Sender<SessionEvent>) {
        if self.flushing.swap(true, Ordering::AcqRel) {
            return;
        }
        let pending = Arc::clone(&self.pending);
        let flushing = Arc::clone(&self.flushing);
        tokio::spawn(async move {
            let result = tx.reserve().await;
            match result {
                Ok(permit) => {
                    let rect = pending.lock().unwrap_or_else(|e| e.into_inner()).take();
                    if let Some(rect) = rect {
                        permit.send(SessionEvent::FramebufferDirty { rect });
                    }
                    // Permit dropped unused if no pending — slot released.
                }
                Err(_) => {
                    // Channel closed.
                }
            }
            flushing.store(false, Ordering::Release);
            // Race: dirty may have arrived while we held flushing=true.
            let coalescer = DirtyCoalescer {
                pending,
                flushing: Arc::clone(&flushing),
            };
            if coalescer.has_pending() {
                coalescer.try_flush(&tx);
            }
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::sync::mpsc;

    fn rect(x: i32, y: i32, w: u32, h: u32) -> Rect {
        Rect { x, y, w, h }
    }

    #[tokio::test]
    async fn full_queue_coalesces_overflow_into_pending_then_drains() {
        let (tx, mut rx) = mpsc::channel::<SessionEvent>(1);
        let c = DirtyCoalescer::new();

        c.send_dirty(&tx, rect(0, 0, 10, 10));
        // Channel capacity 1 — next dirties must coalesce, not block.
        c.send_dirty(&tx, rect(20, 0, 5, 5));
        c.send_dirty(&tx, rect(0, 30, 2, 2));

        let first = rx.recv().await.expect("first dirty");
        match first {
            SessionEvent::FramebufferDirty { rect: r } => {
                assert_eq!(r, rect(0, 0, 10, 10));
            }
            other => panic!("unexpected {other:?}"),
        }

        // Flusher or try_flush after recv should deliver union of overflow.
        let second = tokio::time::timeout(std::time::Duration::from_secs(2), rx.recv())
            .await
            .expect("timeout waiting coalesced dirty")
            .expect("channel closed");
        match second {
            SessionEvent::FramebufferDirty { rect: r } => {
                // union of (20,0,5,5) and (0,30,2,2) = (0,0,25,32)
                assert_eq!(r, rect(0, 0, 25, 32));
            }
            other => panic!("unexpected {other:?}"),
        }

        assert!(!c.has_pending());
        assert!(rx.try_recv().is_err());
    }

    #[tokio::test]
    async fn many_overflows_union_to_single_coverage() {
        let (tx, mut rx) = mpsc::channel::<SessionEvent>(1);
        let c = DirtyCoalescer::new();

        c.send_dirty(&tx, rect(0, 0, 1, 1));
        for i in 1..50 {
            c.send_dirty(&tx, rect(i, 0, 1, 1));
        }

        let mut covered: Option<Rect> = None;
        while let Ok(Some(ev)) =
            tokio::time::timeout(std::time::Duration::from_millis(500), rx.recv()).await
        {
            if let SessionEvent::FramebufferDirty { rect: r } = ev {
                covered = Some(match covered {
                    Some(c) => c.union(r),
                    None => r,
                });
            }
            if !c.has_pending() && rx.is_empty() {
                // Give flusher a tick.
                tokio::task::yield_now().await;
                if !c.has_pending() && rx.is_empty() {
                    break;
                }
            }
        }

        let covered = covered.expect("expected dirty events");
        // All points 0..50 on x axis, height 1 → union (0,0,50,1)
        assert_eq!(covered, rect(0, 0, 50, 1));
        assert!(!c.has_pending());
    }
}
