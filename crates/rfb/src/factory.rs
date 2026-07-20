//! SessionFactory for RFB.

use crate::session::connect_tcp;
use crate::vencrypt::TlsOptions;
use helmhost_core::{
    BoxFuture, ConnectTarget, Creds, ProtocolId, SessionFactory, SessionHandle, SessionManager,
};
use std::sync::Mutex;

/// Creates TCP RFB sessions (async task + queue).
///
/// Optional live interop: set `HELMHOST_RFB=host:port` (and optionally
/// `HELMHOST_RFB_PASSWORD`) then run the ignored `live_rfb_optional` test
/// against a local RFB server.
pub struct RfbSessionFactory {
    ids: Mutex<SessionManager>,
    tls: TlsOptions,
    prefer_vencrypt: bool,
}

impl RfbSessionFactory {
    pub fn new() -> Self {
        Self {
            ids: Mutex::new(SessionManager::new()),
            tls: TlsOptions::default(),
            prefer_vencrypt: false,
        }
    }

    pub fn with_tls(mut self, tls: TlsOptions) -> Self {
        self.tls = tls;
        self
    }

    pub fn prefer_vencrypt(mut self, yes: bool) -> Self {
        self.prefer_vencrypt = yes;
        self
    }

    pub fn configure_connect(&mut self, tls: TlsOptions, prefer_vencrypt: bool) {
        self.tls = tls;
        self.prefer_vencrypt = prefer_vencrypt;
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
        target: ConnectTarget,
        creds: Creds,
    ) -> BoxFuture<'_, Result<SessionHandle, String>> {
        let tls = self.tls.clone();
        let prefer_vencrypt = self.prefer_vencrypt;
        Box::pin(async move {
            let id = self
                .ids
                .lock()
                .map_err(|_| "session id lock poisoned".to_string())?
                .alloc_id();
            let handle =
                connect_tcp(id, &target.host, target.port, creds, tls, prefer_vencrypt).await?;
            if let Ok(mut g) = self.ids.lock() {
                g.insert(id, handle.commands.clone());
            }
            Ok(handle)
        })
    }
}

/// Test helper: handshake over an existing TCP stream (no VeNCrypt).
pub async fn connect_stream(
    stream: tokio::net::TcpStream,
    creds: &Creds,
) -> Result<SessionHandle, String> {
    crate::session::connect_stream(
        helmhost_core::SessionId(1),
        stream,
        "localhost",
        creds.clone(),
        TlsOptions::default(),
        false,
    )
    .await
}
