//! SessionFactory for RFB.

use crate::encoding::{encodings_with_quality_compress, preferred_encodings, BandwidthPreset};
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
    bandwidth: BandwidthPreset,
    quality_level: Option<i32>,
    compress_level: Option<i32>,
}

impl RfbSessionFactory {
    pub fn new() -> Self {
        Self {
            ids: Mutex::new(SessionManager::new()),
            tls: TlsOptions::default(),
            prefer_vencrypt: false,
            bandwidth: BandwidthPreset::default(),
            quality_level: Some(8),
            compress_level: Some(2),
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

    /// Set bandwidth profile and optional Tight quality/compress levels.
    ///
    /// When `quality` or `compress` is `Some`, Tight is promoted to first in
    /// the encoding list and the corresponding pseudo-encodings are appended.
    pub fn configure_bandwidth(
        &mut self,
        bandwidth: BandwidthPreset,
        quality: Option<i32>,
        compress: Option<i32>,
    ) {
        self.bandwidth = bandwidth;
        self.quality_level = quality;
        self.compress_level = compress;
    }

    fn build_encodings(&self) -> Vec<i32> {
        encodings_with_quality_compress(self.bandwidth, self.quality_level, self.compress_level)
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
        let encodings = self.build_encodings();
        Box::pin(async move {
            let id = self
                .ids
                .lock()
                .map_err(|_| "session id lock poisoned".to_string())?
                .alloc_id();
            let handle = connect_tcp(
                id,
                &target.host,
                target.port,
                creds,
                tls,
                prefer_vencrypt,
                &encodings,
            )
            .await?;
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
        &preferred_encodings(),
    )
    .await
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::encoding::{
        compress_level_encoding, quality_level_encoding, ENC_CONTINUOUS_UPDATES, ENC_TIGHT,
    };

    #[test]
    fn default_factory_encodings_tight_first_q8_c2_cu() {
        let f = RfbSessionFactory::new();
        let e = f.build_encodings();
        assert_eq!(e[0], ENC_TIGHT);
        assert!(e.contains(&ENC_CONTINUOUS_UPDATES));
        assert!(e.contains(&quality_level_encoding(8))); // -24
        assert!(e.contains(&compress_level_encoding(2))); // -254
        assert_eq!(quality_level_encoding(8), -24);
        assert_eq!(compress_level_encoding(2), -254);
    }
}
