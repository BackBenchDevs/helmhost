//! VeNCrypt security-type negotiation (pre-TLS) and TLS wrap helpers.
//!
//! Subtype IDs match TigerVNC [`Security.h`](secTypePlain = 256 … secTypeX509Plain = 262).

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

/// VeNCrypt / Plain username+password (no TLS).
pub const VENCRYPT_PLAIN: u32 = 256;
/// TLS + None.
pub const VENCRYPT_TLSNONE: u32 = 257;
/// TLS + VNC Auth.
pub const VENCRYPT_TLSVNC: u32 = 258;
/// TLS + Plain.
pub const VENCRYPT_TLSPLAIN: u32 = 259;
/// X.509 TLS + None.
pub const VENCRYPT_X509NONE: u32 = 260;
/// X.509 TLS + VNC Auth.
pub const VENCRYPT_X509VNC: u32 = 261;
/// X.509 TLS + Plain.
pub const VENCRYPT_X509PLAIN: u32 = 262;

#[derive(Debug, Clone, Default)]
pub struct TlsOptions {
    /// When true, accept invalid/self-signed server certificates (lab only).
    pub danger_accept_invalid_certs: bool,
}

/// True when the subtype requires a TLS handshake before auth.
pub fn vencrypt_subtype_needs_tls(subtype: u32) -> bool {
    matches!(
        subtype,
        VENCRYPT_TLSNONE
            | VENCRYPT_TLSVNC
            | VENCRYPT_TLSPLAIN
            | VENCRYPT_X509NONE
            | VENCRYPT_X509VNC
            | VENCRYPT_X509PLAIN
    )
}

/// True when the subtype uses X.509 certificate verification (vs TLS\* lab/anon style).
pub fn vencrypt_subtype_is_x509(subtype: u32) -> bool {
    matches!(
        subtype,
        VENCRYPT_X509NONE | VENCRYPT_X509VNC | VENCRYPT_X509PLAIN
    )
}

/// True when the subtype uses anonymous TLS (VeNCrypt TLS\* prefix).
///
/// rustls cannot negotiate ANON-DH/ANON-ECDH; prefer [`vencrypt_subtype_is_x509`] peers.
pub fn vencrypt_subtype_is_anon_tls(subtype: u32) -> bool {
    matches!(
        subtype,
        VENCRYPT_TLSNONE | VENCRYPT_TLSVNC | VENCRYPT_TLSPLAIN
    )
}

/// Pick a VeNCrypt subtype from the server list.
///
/// Prefers X509\* over TLS\* because Helmhost uses rustls, which does not support
/// the anonymous ciphers required by VeNCrypt TLS\* subtypes.
pub fn pick_vencrypt_subtype(
    subtypes: &[u32],
    have_user: bool,
    have_password: bool,
) -> Result<u32, String> {
    let has = |t: u32| subtypes.contains(&t);

    if have_user && have_password {
        if has(VENCRYPT_X509PLAIN) {
            return Ok(VENCRYPT_X509PLAIN);
        }
        if has(VENCRYPT_TLSPLAIN) {
            return Ok(VENCRYPT_TLSPLAIN);
        }
    }
    if have_password {
        if has(VENCRYPT_X509VNC) {
            return Ok(VENCRYPT_X509VNC);
        }
        if has(VENCRYPT_TLSVNC) {
            return Ok(VENCRYPT_TLSVNC);
        }
    }
    if has(VENCRYPT_X509NONE) {
        return Ok(VENCRYPT_X509NONE);
    }
    if has(VENCRYPT_TLSNONE) {
        return Ok(VENCRYPT_TLSNONE);
    }
    if have_user && have_password && has(VENCRYPT_PLAIN) {
        return Ok(VENCRYPT_PLAIN);
    }
    // Some stacks advertise classic types as VeNCrypt subtypes.
    if has(u32::from(SEC_NONE)) {
        return Ok(u32::from(SEC_NONE));
    }
    if have_password && has(u32::from(SEC_VNC_AUTH)) {
        return Ok(u32::from(SEC_VNC_AUTH));
    }
    if has(u32::from(SEC_VNC_AUTH)) {
        return Ok(u32::from(SEC_VNC_AUTH));
    }

    // Plain-family only (e.g. [TLSPlain, X509Plain]): still select so auth can
    // return NEED_USERNAME_PASSWORD instead of failing at subtype pick.
    // Prefer X509Plain — rustls can complete that handshake.
    if has(VENCRYPT_X509PLAIN) {
        return Ok(VENCRYPT_X509PLAIN);
    }
    if has(VENCRYPT_TLSPLAIN) {
        return Ok(VENCRYPT_TLSPLAIN);
    }
    if has(VENCRYPT_PLAIN) {
        return Ok(VENCRYPT_PLAIN);
    }

    Err(format!("VeNCrypt: no supported subtype in {subtypes:?}"))
}

/// Negotiate VeNCrypt version + subtype on a cleartext stream. Returns chosen subtype.
///
/// Wire (TigerVNC `CSecurityVeNCrypt`):
/// 1. Server → major, minor
/// 2. Client → 0.2 (or 0.0 if unsupported)
/// 3. Server → U8 version ACK (`0` = OK)
/// 4. Server → U8 n, then n×U32 subtypes
/// 5. Client → U32 chosen subtype
/// 6. Server → U8 subtype ACK (`1` = OK)
pub async fn negotiate_vencrypt_subtype<S: AsyncRead + AsyncWrite + Unpin>(
    stream: &mut S,
    have_user: bool,
    have_password: bool,
) -> Result<u32, String> {
    let ver = read_exact(stream, 2).await?;
    let major = ver[0];
    let minor = ver[1];
    if major == 0 && minor < 2 {
        // Reject unsupported version the way TigerVNC does (send 0.0).
        write_all(stream, &[0, 0]).await?;
        return Err(format!("VeNCrypt version {major}.{minor} too old"));
    }
    write_all(stream, &[0, 2]).await?;

    // Version agreement: 0 = OK (TigerVNC). Missing this read causes n=0 subtype false positives.
    let ack = read_exact(stream, 1).await?;
    if ack[0] != 0 {
        return Err(format!(
            "VeNCrypt: server rejected version 0.2 (status={})",
            ack[0]
        ));
    }

    let nbuf = read_exact(stream, 1).await?;
    let n = nbuf[0] as usize;
    if n == 0 {
        return Err(
            "VeNCrypt: server offered zero subtypes (server VeNCrypt misconfigured)".into(),
        );
    }
    let raw = read_exact(stream, n * 4).await?;
    let mut subtypes = Vec::with_capacity(n);
    for chunk in raw.chunks_exact(4) {
        subtypes.push(u32::from_be_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]));
    }

    let chosen = pick_vencrypt_subtype(&subtypes, have_user, have_password)?;
    // Return NEED before writing the subtype so the server is not left mid-handshake
    // (classic UNIX_LOGIN does the same before writing the security type).
    if matches!(
        chosen,
        VENCRYPT_PLAIN | VENCRYPT_TLSPLAIN | VENCRYPT_X509PLAIN
    ) && (!have_user || !have_password)
    {
        return Err(helmhost_core::NEED_USERNAME_PASSWORD.to_string());
    }
    if (matches!(chosen, VENCRYPT_TLSVNC | VENCRYPT_X509VNC)
        || chosen == u32::from(SEC_VNC_AUTH))
        && !have_password
    {
        return Err(helmhost_core::NEED_PASSWORD.to_string());
    }
    write_all(stream, &chosen.to_be_bytes()).await?;

    let sub_ack = read_exact(stream, 1).await?;
    if sub_ack[0] != 1 {
        return Err(format!("VeNCrypt subtype rejected status={}", sub_ack[0]));
    }
    Ok(chosen)
}

fn build_client_config(opts: &TlsOptions, allow_invalid: bool) -> Result<ClientConfig, String> {
    let provider = rustls::crypto::ring::default_provider();
    if allow_invalid || opts.danger_accept_invalid_certs {
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

fn map_tls_connect_error(subtype: u32, err: impl std::fmt::Display) -> String {
    let msg = err.to_string();
    if vencrypt_subtype_is_anon_tls(subtype) {
        return format!(
            "TLS connect: {msg}; VeNCrypt TLS* subtypes need anonymous TLS \
             (unsupported by rustls) — use an X509* subtype (enable Accept invalid \
             certificates for lab PEMs) or a GnuTLS-based viewer for TLSPlain/TLSVnc"
        );
    }
    format!("TLS connect: {msg}")
}

/// Wrap TCP in TLS. For TLS\* subtypes (non-X509), accept invalid certs by default
/// because many VeNCrypt servers use self-signed/anon-style certs. X509\* respects
/// [`TlsOptions::danger_accept_invalid_certs`].
pub async fn wrap_tcp_tls(
    stream: TcpStream,
    host: &str,
    opts: &TlsOptions,
    subtype: u32,
) -> Result<TlsStream<TcpStream>, String> {
    let allow_invalid = !vencrypt_subtype_is_x509(subtype) || opts.danger_accept_invalid_certs;
    let config = Arc::new(build_client_config(opts, allow_invalid)?);
    let connector = TlsConnector::from(config);
    let name = ServerName::try_from(host.to_string()).map_err(|e| e.to_string())?;
    connector
        .connect(name, stream)
        .await
        .map_err(|e| map_tls_connect_error(subtype, e))
}
