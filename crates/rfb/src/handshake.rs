//! RFB handshake: version, security, init (async).

use crate::auth::encrypt_challenge;
use crate::io::{read_exact, write_all};
use crate::pixel_format::PixelFormat;
use helmhost_core::Creds;
use tokio::io::{AsyncRead, AsyncWrite};

pub const RFB_003_008: &[u8] = b"RFB 003.008\n";
pub const SEC_NONE: u8 = 1;
pub const SEC_VNC_AUTH: u8 = 2;
/// TigerVNC RSA-AES-128 (all encrypted).
pub const SEC_RA2: u8 = 5;
/// TigerVNC RSA-AES-128 (auth only).
pub const SEC_RA2NE: u8 = 6;
pub const SEC_VENCRYPT: u8 = 19;
/// Tight-style Unix Login (username + password) **or** TigerVNC RA2_256.
///
/// Disambiguation: if type 129 appears with 5/6/130, treat as RA256; if alone
/// with a username, prefer Unix Login (see [`pick_security`]).
pub const SEC_UNIX_LOGIN: u8 = 129;
/// TigerVNC RSA-AES-256 (all encrypted). Same numeric id as [`SEC_UNIX_LOGIN`].
pub const SEC_RA256: u8 = 129;
/// TigerVNC RSA-AES-256 (auth only).
pub const SEC_RANE256: u8 = 130;
pub const SEC_RESULT_OK: u32 = 0;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ServerInit {
    pub width: u16,
    pub height: u16,
    pub pixel_format: PixelFormat,
    pub name: String,
}

/// Parse server version line (12 bytes including newline).
pub fn parse_version(buf: &[u8]) -> Result<String, String> {
    if buf.len() < 12 {
        return Err("version truncated".into());
    }
    std::str::from_utf8(&buf[..12])
        .map(|s| s.to_string())
        .map_err(|e| e.to_string())
}

/// Extract major/minor from an `RFB 003.008\n`-style version string.
pub fn version_major_minor(ver: &str) -> Result<(u16, u16), String> {
    let s = ver.trim();
    if !s.starts_with("RFB ") || s.len() < 11 {
        return Err(format!("bad version: {ver:?}"));
    }
    let major: u16 = s[4..7]
        .parse()
        .map_err(|_| format!("bad major in {ver:?}"))?;
    let minor: u16 = s[8..11]
        .parse()
        .map_err(|_| format!("bad minor in {ver:?}"))?;
    Ok((major, minor))
}

pub fn encode_client_version() -> [u8; 12] {
    let mut out = [0u8; 12];
    out.copy_from_slice(RFB_003_008);
    out
}

pub fn encode_client_version_33() -> [u8; 12] {
    *b"RFB 003.003\n"
}

async fn read_security_failure_reason<S: AsyncRead + Unpin>(stream: &mut S) -> String {
    let len_buf = match read_exact(stream, 4).await {
        Ok(b) => b,
        Err(_) => return String::new(),
    };
    let len = u32::from_be_bytes([len_buf[0], len_buf[1], len_buf[2], len_buf[3]]) as usize;
    if !(1..=4096).contains(&len) {
        return String::new();
    }
    match read_exact(stream, len).await {
        Ok(raw) => String::from_utf8_lossy(&raw).trim().to_string(),
        Err(_) => String::new(),
    }
}

fn reject_with_reason(reason: String) -> String {
    if reason.is_empty() {
        "server sent zero security types".into()
    } else {
        format!("server rejected connection: {reason}")
    }
}

pub fn parse_security_types(buf: &[u8]) -> Result<Vec<u8>, String> {
    if buf.is_empty() {
        return Err("empty security".into());
    }
    let n = buf[0] as usize;
    if n == 0 {
        return Err("server rejected security (zero types)".into());
    }
    if buf.len() < 1 + n {
        return Err("security types truncated".into());
    }
    Ok(buf[1..1 + n].to_vec())
}

pub fn pick_security(
    types: &[u8],
    have_password: bool,
    prefer_vencrypt: bool,
) -> Result<u8, String> {
    pick_security_ex(types, have_password, false, prefer_vencrypt)
}

/// Like [`pick_security`] with username presence (disambiguates type 129).
pub fn pick_security_ex(
    types: &[u8],
    have_password: bool,
    have_username: bool,
    prefer_vencrypt: bool,
) -> Result<u8, String> {
    let has = |t: u8| types.contains(&t);
    let has_ra_other = has(SEC_RA2) || has(SEC_RA2NE) || has(SEC_RANE256);
    // Type 129 is RA256 when RA family present, or when no username (can't be Unix Login).
    let treat_129_as_ra256 = has(129) && (has_ra_other || !have_username);
    let has_classic =
        has(SEC_NONE) || has(SEC_VNC_AUTH) || (has(129) && have_username && !has_ra_other);

    if has(SEC_VENCRYPT) && (prefer_vencrypt || !has_classic) {
        return Ok(SEC_VENCRYPT);
    }

    // RSA-AES (prefer ne variants when both available — clearer session path).
    if treat_129_as_ra256 || has_ra_other {
        if has(SEC_RANE256) {
            return Ok(SEC_RANE256);
        }
        if treat_129_as_ra256 {
            return Ok(SEC_RA256);
        }
        if has(SEC_RA2NE) {
            return Ok(SEC_RA2NE);
        }
        if has(SEC_RA2) {
            return Ok(SEC_RA2);
        }
    }

    if have_password && has(SEC_VNC_AUTH) {
        return Ok(SEC_VNC_AUTH);
    }
    if has(SEC_NONE) {
        return Ok(SEC_NONE);
    }
    if has(SEC_VNC_AUTH) {
        return Ok(SEC_VNC_AUTH);
    }
    if has(129) && have_username && !has_ra_other {
        return Ok(SEC_UNIX_LOGIN);
    }
    if has(SEC_VENCRYPT) {
        return Ok(SEC_VENCRYPT);
    }
    Err(format!("no supported security in {types:?}"))
}

pub fn parse_security_result(buf: &[u8]) -> Result<(), String> {
    if buf.len() < 4 {
        return Err("security result truncated".into());
    }
    let code = u32::from_be_bytes([buf[0], buf[1], buf[2], buf[3]]);
    if code == SEC_RESULT_OK {
        Ok(())
    } else {
        Err(format!("security result failed code={code}"))
    }
}

pub fn encode_client_init(shared: bool) -> [u8; 1] {
    [u8::from(shared)]
}

pub fn parse_server_init(buf: &[u8]) -> Result<ServerInit, String> {
    if buf.len() < 24 {
        return Err("ServerInit truncated".into());
    }
    let width = u16::from_be_bytes([buf[0], buf[1]]);
    let height = u16::from_be_bytes([buf[2], buf[3]]);
    let pixel_format = PixelFormat::decode(&buf[4..20])?;
    let name_len = u32::from_be_bytes([buf[20], buf[21], buf[22], buf[23]]) as usize;
    if buf.len() < 24 + name_len {
        return Err("ServerInit name truncated".into());
    }
    let name = String::from_utf8_lossy(&buf[24..24 + name_len]).into_owned();
    Ok(ServerInit {
        width,
        height,
        pixel_format,
        name,
    })
}

pub async fn vnc_auth_exchange<S: AsyncRead + AsyncWrite + Unpin>(
    stream: &mut S,
    password: &str,
) -> Result<(), String> {
    let challenge = read_exact(stream, 16).await?;
    let mut ch = [0u8; 16];
    ch.copy_from_slice(&challenge);
    let response = encrypt_challenge(password, &ch);
    write_all(stream, &response).await?;
    Ok(())
}

/// Encode Tight Unix Login / Plain credentials (UTF-8 lengths + bytes).
pub fn encode_unix_login(username: &str, password: &str) -> Vec<u8> {
    let user = username.as_bytes();
    let pass = password.as_bytes();
    let mut out = Vec::with_capacity(8 + user.len() + pass.len());
    out.extend_from_slice(&(user.len() as u32).to_be_bytes());
    out.extend_from_slice(&(pass.len() as u32).to_be_bytes());
    out.extend_from_slice(user);
    out.extend_from_slice(pass);
    out
}

pub async fn unix_login_exchange<S: AsyncRead + AsyncWrite + Unpin>(
    stream: &mut S,
    username: &str,
    password: &str,
) -> Result<(), String> {
    write_all(stream, &encode_unix_login(username, password)).await?;
    Ok(())
}

/// Classic (non-TLS) security + ClientInit/ServerInit. Caller handles VeNCrypt separately.
pub async fn handshake_security_and_init<S: AsyncRead + AsyncWrite + Unpin>(
    stream: &mut S,
    creds: &Creds,
    prefer_vencrypt: bool,
) -> Result<(ServerInit, Option<u8>), String> {
    let ver = read_exact(stream, 12).await?;
    let ver_str = parse_version(&ver)?;
    let (major, minor) = version_major_minor(&ver_str)?;

    // RFB 3.3 (incl. TigerVNC IP blacklist): U32 security type, not U8 count.
    // Blacklist sends "RFB 003.003\n" + U32(0) + reason without a normal 3.8 list.
    if major == 3 && minor < 7 {
        write_all(stream, &encode_client_version_33()).await?;
        let sec_buf = read_exact(stream, 4).await?;
        let sec = u32::from_be_bytes([sec_buf[0], sec_buf[1], sec_buf[2], sec_buf[3]]);
        if sec == 0 {
            let reason = read_security_failure_reason(stream).await;
            return Err(reject_with_reason(reason));
        }
        let sec_u8 = u8::try_from(sec).map_err(|_| format!("bad 3.3 security type {sec}"))?;
        let have_pw = creds.password.as_ref().is_some_and(|p| !p.is_empty());
        match sec_u8 {
            SEC_NONE => {}
            SEC_VNC_AUTH => {
                if !have_pw {
                    return Err(helmhost_core::NEED_PASSWORD.to_string());
                }
                let pw = creds.password.as_deref().unwrap();
                vnc_auth_exchange(stream, pw).await?;
                let result = read_exact(stream, 4).await?;
                parse_security_result(&result)?;
            }
            other => {
                return Err(format!(
                    "RFB 3.3 security type {other} unsupported (VeNCrypt needs 3.7+)"
                ));
            }
        }
        let init = finish_client_server_init(stream).await?;
        return Ok((init, None));
    }

    write_all(stream, &encode_client_version()).await?;

    let nbuf = read_exact(stream, 1).await?;
    let n = nbuf[0] as usize;
    if n == 0 {
        let reason = read_security_failure_reason(stream).await;
        return Err(reject_with_reason(reason));
    }
    let rest = read_exact(stream, n).await?;
    let mut full = Vec::with_capacity(1 + n);
    full.push(nbuf[0]);
    full.extend_from_slice(&rest);
    let types = parse_security_types(&full)?;

    let have_pw = creds.password.as_ref().is_some_and(|p| !p.is_empty());
    let have_user = creds.username.as_ref().is_some_and(|u| !u.is_empty());
    let sec = pick_security_ex(&types, have_pw, have_user, prefer_vencrypt)?;
    if sec == SEC_VNC_AUTH && !have_pw {
        return Err(helmhost_core::NEED_PASSWORD.to_string());
    }
    if sec == SEC_UNIX_LOGIN && (!have_user || !have_pw) {
        return Err(helmhost_core::NEED_USERNAME_PASSWORD.to_string());
    }
    // VeNCrypt Plain/X509Plain need a username. Returning NEED before writing type 19
    // avoids aborting mid-VeNCrypt (blacklist → RFB 3.3 "Too many security failures").
    if sec == SEC_VENCRYPT && !have_user {
        return Err(helmhost_core::NEED_USERNAME_PASSWORD.to_string());
    }
    write_all(stream, &[sec]).await?;

    if sec == SEC_VENCRYPT {
        return Ok((
            ServerInit {
                width: 0,
                height: 0,
                pixel_format: PixelFormat::rgb888_le(),
                name: String::new(),
            },
            Some(SEC_VENCRYPT),
        ));
    }

    // Type 129 is both Unix Login and RA256 — only continue as RSA-AES when
    // pick_security_ex treated it as RA (RA family present or no username).
    let has_ra_other = types
        .iter()
        .any(|&t| t == SEC_RA2 || t == SEC_RA2NE || t == SEC_RANE256);
    let is_rsa_aes = matches!(sec, SEC_RA2 | SEC_RA2NE | SEC_RANE256)
        || (sec == SEC_RA256 && (has_ra_other || !have_user));
    if is_rsa_aes {
        return Ok((
            ServerInit {
                width: 0,
                height: 0,
                pixel_format: PixelFormat::rgb888_le(),
                name: String::new(),
            },
            Some(sec),
        ));
    }

    match sec {
        SEC_NONE => {}
        SEC_VNC_AUTH => {
            let pw = creds
                .password
                .as_deref()
                .ok_or_else(|| helmhost_core::NEED_PASSWORD.to_string())?;
            vnc_auth_exchange(stream, pw).await?;
        }
        SEC_UNIX_LOGIN => {
            let user = creds
                .username
                .as_deref()
                .filter(|u| !u.is_empty())
                .ok_or_else(|| helmhost_core::NEED_USERNAME_PASSWORD.to_string())?;
            let pw = creds
                .password
                .as_deref()
                .filter(|p| !p.is_empty())
                .ok_or_else(|| helmhost_core::NEED_USERNAME_PASSWORD.to_string())?;
            unix_login_exchange(stream, user, pw).await?;
        }
        other => return Err(format!("unsupported security {other}")),
    }

    let result = read_exact(stream, 4).await?;
    parse_security_result(&result)?;

    let init = finish_client_server_init(stream).await?;
    Ok((init, None))
}

pub async fn finish_client_server_init<S: AsyncRead + AsyncWrite + Unpin>(
    stream: &mut S,
) -> Result<ServerInit, String> {
    write_all(stream, &encode_client_init(true)).await?;
    let head = read_exact(stream, 24).await?;
    let name_len = u32::from_be_bytes([head[20], head[21], head[22], head[23]]) as usize;
    let name_bytes = read_exact(stream, name_len).await?;
    let mut init_buf = head;
    init_buf.extend_from_slice(&name_bytes);
    parse_server_init(&init_buf)
}
