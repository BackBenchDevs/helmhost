//! Shared multi-thread Tokio runtime for hosting multiple sessions.

use std::future::Future;
use tokio::runtime::{Builder, Handle, Runtime};
use tokio::task::JoinHandle;

/// Owns a multi-thread Tokio runtime used for concurrent sessions.
pub struct HelmRuntime {
    rt: Runtime,
}

impl HelmRuntime {
    pub fn new() -> Result<Self, String> {
        let rt = Builder::new_multi_thread()
            .enable_all()
            .thread_name("helmhost")
            .build()
            .map_err(|e| e.to_string())?;
        Ok(Self { rt })
    }

    pub fn handle(&self) -> Handle {
        self.rt.handle().clone()
    }

    pub fn spawn<F>(&self, future: F) -> JoinHandle<F::Output>
    where
        F: Future + Send + 'static,
        F::Output: Send + 'static,
    {
        self.rt.spawn(future)
    }
}

impl Default for HelmRuntime {
    fn default() -> Self {
        Self::new().expect("HelmRuntime")
    }
}
