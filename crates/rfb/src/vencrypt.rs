//! VeNCrypt security-type negotiation (pre-TLS) and TLS wrap helpers.

use crate::handshake::{SEC_NONE, SEC_VNC_AUTH};
use crate::io::{read_exact, write_all};
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::pki_types::{CertificateDer, ServerName, UnixTime};
use rustls::{
    ClientConfig, DigitallySignedStruct, Error as TlsError, RootCertStore, SignatureScheme,
};
use std::sync::Arc;
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::net::TcpStream;
use tokio_rustls::client::TlsStream;
use tokio_rustls::TlsConnector;

/// VeNCrypt subtype: TLS + None auth afterward.
pub const VENCRYPT_TLSNONE: u32 = 256;
/// VeNCrypt subtype: TLS + VNC Auth afterward.
pub const VENCRYPT_TLSVNC: u32 = 257;

#[derive(Debug, Clone, Default)]
pub struct TlsOptions {
    /// When true, accept invalid/self-signed server certificates (lab only).
    pub danger_accept_invalid_certs: bool,
}

/// Negotiate VeNCrypt version + subtype on a cleartext stream. Returns chosen subtype.
pub async fn negotiate_vencrypt_subtype<S: AsyncRead + AsyncWrite + Unpin>(
    stream: &mut S,
    have_password: bool,
) -> Result<u32, String> {
    let ver = read_exact(stream, 2).await?;
    let major = ver[0];
    let minor = ver[1];
    if major == 0 && minor < 2 {
        return Err(format!("VeNCrypt version {major}.{minor} too old"));
    }
    write_all(stream, &[0, 2]).await?;

    let nbuf = read_exact(stream, 1).await?;
    let n = nbuf[0] as usize;
    if n == 0 {
        return Err(
            "VeNCrypt: server offered zero subtypes (try disabling Prefer VeNCrypt/TLS)".into(),
        );
    }
    let raw = read_exact(stream, n * 4).await?;
    let mut subtypes = Vec::with_capacity(n);
    for chunk in raw.chunks_exact(4) {
        subtypes.push(u32::from_be_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]));
    }

    let chosen = if have_password && subtypes.contains(&VENCRYPT_TLSVNC) {
        VENCRYPT_TLSVNC
    } else if subtypes.contains(&VENCRYPT_TLSNONE) {
        VENCRYPT_TLSNONE
    } else if subtypes.contains(&VENCRYPT_TLSVNC) {
        VENCRYPT_TLSVNC
    } else if subtypes.contains(&u32::from(SEC_NONE)) {
        u32::from(SEC_NONE)
    } else if subtypes.contains(&u32::from(SEC_VNC_AUTH)) {
        u32::from(SEC_VNC_AUTH)
    } else {
        return Err(format!("VeNCrypt: no supported subtype in {subtypes:?}"));
    };

    write_all(stream, &chosen.to_be_bytes()).await?;

    let ack = read_exact(stream, 1).await?;
    if ack[0] != 1 {
        return Err(format!("VeNCrypt subtype rejected status={}", ack[0]));
    }
    Ok(chosen)
}

fn build_client_config(opts: &TlsOptions) -> Result<ClientConfig, String> {
    let provider = rustls::crypto::ring::default_provider();
    if opts.danger_accept_invalid_certs {
        return ClientConfig::builder_with_provider(provider.into())
            .with_safe_default_protocol_versions()
            .map_err(|e| e.to_string())?
            .dangerous()
            .with_custom_certificate_verifier(Arc::new(NoVerifier))
            .with_no_client_auth()
            .pipe_ok();
    }
    let mut roots = RootCertStore::empty();
    roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
    ClientConfig::builder_with_provider(provider.into())
        .with_safe_default_protocol_versions()
        .map_err(|e| e.to_string())?
        .with_root_certificates(roots)
        .with_no_client_auth()
        .pipe_ok()
}

trait PipeOk {
    fn pipe_ok(self) -> Result<ClientConfig, String>;
}

impl PipeOk for ClientConfig {
    fn pipe_ok(self) -> Result<ClientConfig, String> {
        Ok(self)
    }
}

#[derive(Debug)]
struct NoVerifier;

impl ServerCertVerifier for NoVerifier {
    fn verify_server_cert(
        &self,
        _end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp_response: &[u8],
        _now: UnixTime,
    ) -> Result<ServerCertVerified, TlsError> {
        Ok(ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, TlsError> {
        Ok(HandshakeSignatureValid::assertion())
    }

    fn verify_tls13_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, TlsError> {
        Ok(HandshakeSignatureValid::assertion())
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        rustls::crypto::ring::default_provider()
            .signature_verification_algorithms
            .supported_schemes()
    }
}

pub async fn wrap_tcp_tls(
    stream: TcpStream,
    host: &str,
    opts: &TlsOptions,
) -> Result<TlsStream<TcpStream>, String> {
    let config = Arc::new(build_client_config(opts)?);
    let connector = TlsConnector::from(config);
    let name = ServerName::try_from(host.to_string()).map_err(|e| e.to_string())?;
    connector
        .connect(name, stream)
        .await
        .map_err(|e| format!("TLS connect: {e}"))
}
