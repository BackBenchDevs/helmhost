//! RFB handshake: version, security, init.

use crate::auth::encrypt_challenge;
use crate::pixel_format::PixelFormat;
use std::io::{Read, Write};

pub const RFB_003_008: &[u8] = b"RFB 003.008\n";
pub const SEC_NONE: u8 = 1;
pub const SEC_VNC_AUTH: u8 = 2;
pub const SEC_RESULT_OK: u32 = 0;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ServerInit {
    pub width: u16,
    pub height: u16,
    pub pixel_format: PixelFormat,
    pub name: String,
}

/// Read exactly `n` bytes.
pub fn read_exact<R: Read>(r: &mut R, n: usize) -> Result<Vec<u8>, String> {
    let mut buf = vec![0u8; n];
    r.read_exact(&mut buf).map_err(|e| e.to_string())?;
    Ok(buf)
}

pub fn write_all<W: Write>(w: &mut W, data: &[u8]) -> Result<(), String> {
    w.write_all(data).map_err(|e| e.to_string())
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

/// After client version: server sends number of security types + list (3.8).
pub fn parse_security_types(buf: &[u8]) -> Result<Vec<u8>, String> {
    if buf.is_empty() {
        return Err("empty security".into());
    }
    let n = buf[0] as usize;
    if n == 0 {
        // Failure: 4-byte reason length follows in full stream; here just error
        return Err("server rejected security (zero types)".into());
    }
    if buf.len() < 1 + n {
        return Err("security types truncated".into());
    }
    Ok(buf[1..1 + n].to_vec())
}

pub fn pick_security(types: &[u8], have_password: bool) -> Result<u8, String> {
    if have_password && types.contains(&SEC_VNC_AUTH) {
        return Ok(SEC_VNC_AUTH);
    }
    if types.contains(&SEC_NONE) {
        return Ok(SEC_NONE);
    }
    if types.contains(&SEC_VNC_AUTH) {
        return Ok(SEC_VNC_AUTH);
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

/// Run VNC auth: read 16-byte challenge, write response.
pub fn vnc_auth_exchange<S: Read + Write>(stream: &mut S, password: &str) -> Result<(), String> {
    let challenge = read_exact(stream, 16)?;
    let mut ch = [0u8; 16];
    ch.copy_from_slice(&challenge);
    let resp = encrypt_challenge(password, &ch);
    write_all(stream, &resp)?;
    Ok(())
}
