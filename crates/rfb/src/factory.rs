//! SessionFactory for RFB.

use crate::session::RfbSession;
use helmhost_core::{
    ConnectTarget, Creds, ProtocolId, RemoteSession, SessionFactory, SessionId, SessionManager,
};
use std::sync::Mutex;

/// Creates TCP RFB sessions.
pub struct RfbSessionFactory {
    ids: Mutex<SessionManager>,
}

impl RfbSessionFactory {
    pub fn new() -> Self {
        Self {
            ids: Mutex::new(SessionManager::new()),
        }
    }
}

impl Default for RfbSessionFactory {
    fn default() -> Self {
        Self::new()
    }
}

impl SessionFactory for RfbSessionFactory {
    fn protocol(&self) -> ProtocolId {
        ProtocolId::RFB
    }

    fn connect(
        &self,
        target: &ConnectTarget,
        creds: &Creds,
    ) -> Result<Box<dyn RemoteSession>, String> {
        let id = self
            .ids
            .lock()
            .map_err(|_| "session id lock poisoned".to_string())?
            .alloc_id();
        let session = RfbSession::connect_tcp(id, &target.host, target.port, creds)?;
        Ok(Box::new(session))
    }
}

/// Test helper: handshake over an existing stream.
pub fn connect_stream<S: std::io::Read + std::io::Write + Send + 'static>(
    stream: S,
    creds: &Creds,
) -> Result<Box<dyn RemoteSession>, String> {
    let session = RfbSession::handshake(SessionId(1), stream, creds)?;
    Ok(Box::new(session))
}
