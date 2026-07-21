//! RFB handshake: version, security, init (async).

use crate::auth::encrypt_challenge;
use crate::io::{read_exact, write_all};
use crate::pixel_format::PixelFormat;
use helmhost_core::Creds;
use tokio::io::{AsyncRead, AsyncWrite};

pub const RFB_003_008: &[u8] = b"RFB 003.008\n";
pub const SEC_NONE: u8 = 1;
pub const SEC_VNC_AUTH: u8 = 2;
pub const SEC_VENCRYPT: u8 = 19;
/// Tight-style Unix Login (username + password).
pub const SEC_UNIX_LOGIN: u8 = 129;
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

pub fn encode_client_version() -> [u8; 12] {
    let mut out = [0u8; 12];
    out.copy_from_slice(RFB_003_008);
    out
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
    allow_vencrypt: bool,
) -> Result<u8, String> {
    if allow_vencrypt && types.contains(&SEC_VENCRYPT) {
        return Ok(SEC_VENCRYPT);
    }
    if have_password && types.contains(&SEC_VNC_AUTH) {
        return Ok(SEC_VNC_AUTH);
    }
    if types.contains(&SEC_NONE) {
        return Ok(SEC_NONE);
    }
    if types.contains(&SEC_VNC_AUTH) {
        return Ok(SEC_VNC_AUTH);
    }
    if types.contains(&SEC_UNIX_LOGIN) {
        return Ok(SEC_UNIX_LOGIN);
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
        Err(format!("security failed code={code}"))
    }
}

pub fn encode_client_init(shared: bool) -> [u8; 1] {
    [u8::from(shared)]
}

pub fn parse_server_init(buf: &[u8]) -> Result<ServerInit, String> {
    if buf.len() < 24 {
        return Err("server init truncated".into());
    }
    let width = u16::from_be_bytes([buf[0], buf[1]]);
    let height = u16::from_be_bytes([buf[2], buf[3]]);
    let pixel_format = PixelFormat::decode(&buf[4..20])?;
    let name_len = u32::from_be_bytes([buf[20], buf[21], buf[22], buf[23]]) as usize;
    if buf.len() < 24 + name_len {
        return Err("server name truncated".into());
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
    let resp = encrypt_challenge(password, &ch);
    write_all(stream, &resp).await?;
    Ok(())
}

/// Classic (non-TLS) security + ClientInit/ServerInit. Caller handles VeNCrypt separately.
pub async fn handshake_security_and_init<S: AsyncRead + AsyncWrite + Unpin>(
    stream: &mut S,
    creds: &Creds,
    prefer_vencrypt: bool,
) -> Result<(ServerInit, Option<u8>), String> {
    let ver = read_exact(stream, 12).await?;
    let _ = parse_version(&ver)?;
    write_all(stream, &encode_client_version()).await?;

    let nbuf = read_exact(stream, 1).await?;
    let n = nbuf[0] as usize;
    if n == 0 {
        return Err("server sent zero security types".into());
    }
    let rest = read_exact(stream, n).await?;
    let mut full = Vec::with_capacity(1 + n);
    full.push(nbuf[0]);
    full.extend_from_slice(&rest);
    let types = parse_security_types(&full)?;

    let have_pw = creds.password.as_ref().is_some_and(|p| !p.is_empty());
    let have_user = creds.username.as_ref().is_some_and(|u| !u.is_empty());
    let sec = pick_security(&types, have_pw, prefer_vencrypt)?;
    if sec == SEC_VNC_AUTH && !have_pw {
        return Err(helmhost_core::NEED_PASSWORD.to_string());
    }
    if sec == SEC_UNIX_LOGIN && (!have_user || !have_pw) {
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
            // Auth exchange for Unix Login is not implemented yet; typed need
            // already surfaced above so the UI can collect username+password.
            return Err("Unix Login auth not yet implemented".into());
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
