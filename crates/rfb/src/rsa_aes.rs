//! TigerVNC RSA-AES security types (RA2 / RA2ne / RA2_256 / RA2ne_256).

use crate::handshake::{SEC_RA2, SEC_RA256, SEC_RA2NE, SEC_RANE256};
use crate::io::{read_exact, write_all};
use aes::{Aes128, Aes256};
use eax::{AeadInPlace, Eax, KeyInit, Nonce, Tag};
use helmhost_core::Creds;
use num_bigint::BigUint;
use rand::rngs::OsRng;
use rand::RngCore;
use rsa::traits::PublicKeyParts;
use rsa::{Pkcs1v15Encrypt, RsaPrivateKey, RsaPublicKey};
use sha1::{Digest, Sha1};
use sha2::Sha256;
use std::pin::Pin;
use std::task::{Context, Poll};
use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};

const MIN_KEY_BITS: u32 = 1024;
const MAX_KEY_BITS: u32 = 8192;
const MAX_MSG: usize = 8192;

pub const RA2_USER_PASS: u8 = 1;
pub const RA2_PASS: u8 = 2;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RsaAesParams {
    pub key_bits: u16,
    pub all_encrypted: bool,
}

impl RsaAesParams {
    pub fn for_sec_type(sec: u8) -> Option<Self> {
        match sec {
            SEC_RA2 => Some(Self {
                key_bits: 128,
                all_encrypted: true,
            }),
            SEC_RA2NE => Some(Self {
                key_bits: 128,
                all_encrypted: false,
            }),
            SEC_RA256 => Some(Self {
                key_bits: 256,
                all_encrypted: true,
            }),
            SEC_RANE256 => Some(Self {
                key_bits: 256,
                all_encrypted: false,
            }),
            _ => None,
        }
    }
}

fn be_u32(n: u32) -> [u8; 4] {
    n.to_be_bytes()
}

fn increment_counter(counter: &mut [u8; 16]) {
    for b in counter.iter_mut() {
        *b = b.wrapping_add(1);
        if *b != 0 {
            break;
        }
    }
}

fn mpz_to_fixed(n: &BigUint, size: usize) -> Vec<u8> {
    let mut v = n.to_bytes_be();
    if v.len() > size {
        v = v[v.len() - size..].to_vec();
    }
    if v.len() < size {
        let mut out = vec![0u8; size - v.len()];
        out.extend_from_slice(&v);
        out
    } else {
        v
    }
}

pub struct EaxKeys {
    key_bytes: usize,
    write_key: [u8; 32],
    read_key: [u8; 32],
    write_counter: [u8; 16],
    read_counter: [u8; 16],
}

impl EaxKeys {
    fn derive(client_random: &[u8], server_random: &[u8], key_bits: u16) -> Self {
        let mut write_key = [0u8; 32];
        let mut read_key = [0u8; 32];
        let key_bytes = (key_bits / 8) as usize;
        if key_bits == 128 {
            let mut ctx = Sha1::new();
            ctx.update(client_random);
            ctx.update(server_random);
            write_key[..16].copy_from_slice(&ctx.finalize()[..16]);
            let mut ctx = Sha1::new();
            ctx.update(server_random);
            ctx.update(client_random);
            read_key[..16].copy_from_slice(&ctx.finalize()[..16]);
        } else {
            let mut ctx = Sha256::new();
            ctx.update(client_random);
            ctx.update(server_random);
            write_key.copy_from_slice(&ctx.finalize());
            let mut ctx = Sha256::new();
            ctx.update(server_random);
            ctx.update(client_random);
            read_key.copy_from_slice(&ctx.finalize());
        }
        Self {
            key_bytes,
            write_key,
            read_key,
            write_counter: [0u8; 16],
            read_counter: [0u8; 16],
        }
    }

    fn seal(&mut self, plaintext: &[u8]) -> Result<Vec<u8>, String> {
        if plaintext.len() > MAX_MSG {
            return Err("RSA-AES message too large".into());
        }
        let ad = (plaintext.len() as u16).to_be_bytes();
        let mut body = plaintext.to_vec();
        let tag = if self.key_bytes == 16 {
            let cipher = Eax::<Aes128>::new_from_slice(&self.write_key[..16])
                .map_err(|e| e.to_string())?;
            cipher
                .encrypt_in_place_detached(Nonce::from_slice(&self.write_counter), &ad, &mut body)
                .map_err(|_| "AES-EAX encrypt failed".to_string())?
        } else {
            let cipher = Eax::<Aes256>::new_from_slice(&self.write_key[..32])
                .map_err(|e| e.to_string())?;
            cipher
                .encrypt_in_place_detached(Nonce::from_slice(&self.write_counter), &ad, &mut body)
                .map_err(|_| "AES-EAX encrypt failed".to_string())?
        };
        increment_counter(&mut self.write_counter);
        let mut out = Vec::with_capacity(2 + body.len() + 16);
        out.extend_from_slice(&ad);
        out.extend_from_slice(&body);
        out.extend_from_slice(tag.as_slice());
        Ok(out)
    }

    async fn open_frame<S: AsyncRead + Unpin>(
        &mut self,
        stream: &mut S,
    ) -> Result<Vec<u8>, String> {
        let hdr = read_exact(stream, 2).await?;
        let length = u16::from_be_bytes([hdr[0], hdr[1]]) as usize;
        if length > MAX_MSG {
            return Err("RSA-AES frame too large".into());
        }
        let rest = read_exact(stream, length + 16).await?;
        let (data, mac) = rest.split_at(length);
        let mut body = data.to_vec();
        let tag = Tag::from_slice(mac);
        if self.key_bytes == 16 {
            let cipher = Eax::<Aes128>::new_from_slice(&self.read_key[..16])
                .map_err(|e| e.to_string())?;
            cipher
                .decrypt_in_place_detached(
                    Nonce::from_slice(&self.read_counter),
                    &hdr,
                    &mut body,
                    tag,
                )
                .map_err(|_| "AES-EAX decrypt/auth failed".to_string())?;
        } else {
            let cipher = Eax::<Aes256>::new_from_slice(&self.read_key[..32])
                .map_err(|e| e.to_string())?;
            cipher
                .decrypt_in_place_detached(
                    Nonce::from_slice(&self.read_counter),
                    &hdr,
                    &mut body,
                    tag,
                )
                .map_err(|_| "AES-EAX decrypt/auth failed".to_string())?;
        }
        increment_counter(&mut self.read_counter);
        Ok(body)
    }
}

fn client_hash(
    key_bits: u16,
    client_n: &[u8],
    client_e: &[u8],
    server_n: &[u8],
    server_e: &[u8],
    key_len_bits: u32,
) -> Vec<u8> {
    let hash_size = if key_bits == 128 { 20 } else { 32 };
    let mut out = vec![0u8; hash_size];
    if key_bits == 128 {
        let mut ctx = Sha1::new();
        ctx.update(be_u32(key_len_bits));
        ctx.update(client_n);
        ctx.update(client_e);
        ctx.update(be_u32(key_len_bits));
        ctx.update(server_n);
        ctx.update(server_e);
        out.copy_from_slice(&ctx.finalize()[..hash_size]);
    } else {
        let mut ctx = Sha256::new();
        ctx.update(be_u32(key_len_bits));
        ctx.update(client_n);
        ctx.update(client_e);
        ctx.update(be_u32(key_len_bits));
        ctx.update(server_n);
        ctx.update(server_e);
        out.copy_from_slice(&ctx.finalize()[..]);
    }
    out
}

fn server_hash(
    key_bits: u16,
    client_n: &[u8],
    client_e: &[u8],
    server_n: &[u8],
    server_e: &[u8],
    key_len_bits: u32,
) -> Vec<u8> {
    let hash_size = if key_bits == 128 { 20 } else { 32 };
    let mut out = vec![0u8; hash_size];
    if key_bits == 128 {
        let mut ctx = Sha1::new();
        ctx.update(be_u32(key_len_bits));
        ctx.update(server_n);
        ctx.update(server_e);
        ctx.update(be_u32(key_len_bits));
        ctx.update(client_n);
        ctx.update(client_e);
        out.copy_from_slice(&ctx.finalize()[..hash_size]);
    } else {
        let mut ctx = Sha256::new();
        ctx.update(be_u32(key_len_bits));
        ctx.update(server_n);
        ctx.update(server_e);
        ctx.update(be_u32(key_len_bits));
        ctx.update(client_n);
        ctx.update(client_e);
        out.copy_from_slice(&ctx.finalize()[..]);
    }
    out
}

/// RSA-AES key exchange + credentials.
/// Returns `Some(keys)` when the session must stay AES-EAX wrapped (RA2 / RA256).
pub async fn rsa_aes_authenticate<S: AsyncRead + AsyncWrite + Unpin>(
    stream: &mut S,
    creds: &Creds,
    params: RsaAesParams,
) -> Result<Option<EaxKeys>, String> {
    let key_bytes_sym = (params.key_bits / 8) as usize;
    let have_user = creds.username.as_ref().is_some_and(|u| !u.is_empty());
    let have_pw = creds.password.as_ref().is_some_and(|p| !p.is_empty());
    if !have_pw {
        return Err(helmhost_core::NEED_PASSWORD.to_string());
    }

    let len_buf = read_exact(stream, 4).await?;
    let server_key_bits = u32::from_be_bytes([len_buf[0], len_buf[1], len_buf[2], len_buf[3]]);
    if !(MIN_KEY_BITS..=MAX_KEY_BITS).contains(&server_key_bits) {
        return Err(format!("RSA-AES: bad server key length {server_key_bits}"));
    }
    let rsa_bytes = ((server_key_bits + 7) / 8) as usize;
    let server_n = read_exact(stream, rsa_bytes).await?;
    let server_e = read_exact(stream, rsa_bytes).await?;
    let server_pub = RsaPublicKey::new(
        BigUint::from_bytes_be(&server_n),
        BigUint::from_bytes_be(&server_e),
    )
    .map_err(|err| format!("RSA-AES server key: {err}"))?;

    let mut rng = OsRng;
    let client_priv = RsaPrivateKey::new(&mut rng, server_key_bits as usize)
        .map_err(|err| format!("RSA-AES generate key: {err}"))?;
    let client_pub = RsaPublicKey::from(&client_priv);
    let client_n = mpz_to_fixed(client_pub.n(), rsa_bytes);
    let client_e = mpz_to_fixed(client_pub.e(), rsa_bytes);
    write_all(stream, &be_u32(server_key_bits)).await?;
    write_all(stream, &client_n).await?;
    write_all(stream, &client_e).await?;

    let mut client_random = vec![0u8; key_bytes_sym];
    rng.fill_bytes(&mut client_random);
    let enc = server_pub
        .encrypt(&mut rng, Pkcs1v15Encrypt, &client_random)
        .map_err(|err| format!("RSA-AES encrypt random: {err}"))?;
    write_all(stream, &(enc.len() as u16).to_be_bytes()).await?;
    write_all(stream, &enc).await?;

    let sz_buf = read_exact(stream, 2).await?;
    let sz = u16::from_be_bytes([sz_buf[0], sz_buf[1]]) as usize;
    if sz != rsa_bytes {
        return Err("RSA-AES: encrypted server random length mismatch".into());
    }
    let enc_server = read_exact(stream, sz).await?;
    let server_random = client_priv
        .decrypt(Pkcs1v15Encrypt, &enc_server)
        .map_err(|err| format!("RSA-AES decrypt server random: {err}"))?;
    if server_random.len() != key_bytes_sym {
        return Err("RSA-AES: bad server random length".into());
    }

    let mut keys = EaxKeys::derive(&client_random, &server_random, params.key_bits);

    let ch = client_hash(
        params.key_bits,
        &client_n,
        &client_e,
        &server_n,
        &server_e,
        server_key_bits,
    );
    write_all(stream, &keys.seal(&ch)?).await?;

    let sh_got = keys.open_frame(stream).await?;
    let sh_exp = server_hash(
        params.key_bits,
        &client_n,
        &client_e,
        &server_n,
        &server_e,
        server_key_bits,
    );
    if sh_got != sh_exp {
        return Err("RSA-AES: hash doesn't match".into());
    }

    let subtype_buf = keys.open_frame(stream).await?;
    if subtype_buf.len() != 1 {
        return Err("RSA-AES: bad subtype frame".into());
    }
    let subtype = subtype_buf[0];
    if subtype != RA2_USER_PASS && subtype != RA2_PASS {
        return Err(format!("RSA-AES: unknown subtype {subtype}"));
    }

    let user = creds.username.as_deref().unwrap_or("");
    let pass = creds.password.as_deref().unwrap_or("");
    if subtype == RA2_USER_PASS && !have_user {
        return Err(helmhost_core::NEED_USERNAME_PASSWORD.to_string());
    }
    if user.len() > 255 || pass.len() > 255 {
        return Err("RSA-AES: username/password too long".into());
    }
    let mut cred_bytes = Vec::new();
    if subtype == RA2_USER_PASS {
        cred_bytes.push(user.len() as u8);
        cred_bytes.extend_from_slice(user.as_bytes());
    } else {
        cred_bytes.push(0);
    }
    cred_bytes.push(pass.len() as u8);
    cred_bytes.extend_from_slice(pass.as_bytes());
    write_all(stream, &keys.seal(&cred_bytes)?).await?;

    if params.all_encrypted {
        Ok(Some(keys))
    } else {
        Ok(None)
    }
}

/// AES-EAX framed transport for RA2 / RA2_256.
pub struct AesEaxIo<S> {
    inner: S,
    keys: EaxKeys,
    read_plain: Vec<u8>,
    read_pos: usize,
    frame_hdr: [u8; 2],
    frame_hdr_got: usize,
    frame_body: Vec<u8>,
    frame_need: usize,
    frame_got: usize,
    write_pending: Vec<u8>,
    write_sent: usize,
    write_plain_report: usize,
}

impl<S> AesEaxIo<S> {
    pub fn new(inner: S, keys: EaxKeys) -> Self {
        Self {
            inner,
            keys,
            read_plain: Vec::new(),
            read_pos: 0,
            frame_hdr: [0; 2],
            frame_hdr_got: 0,
            frame_body: Vec::new(),
            frame_need: 0,
            frame_got: 0,
            write_pending: Vec::new(),
            write_sent: 0,
            write_plain_report: 0,
        }
    }

    fn finish_frame(&mut self) -> std::io::Result<()> {
        let length = u16::from_be_bytes(self.frame_hdr) as usize;
        if self.frame_body.len() != length + 16 {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "AES-EAX frame size",
            ));
        }
        let (data, mac) = self.frame_body.split_at(length);
        let mut body = data.to_vec();
        let tag = Tag::from_slice(mac);
        let res = if self.keys.key_bytes == 16 {
            let cipher = Eax::<Aes128>::new_from_slice(&self.keys.read_key[..16])
                .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidInput, e))?;
            cipher.decrypt_in_place_detached(
                Nonce::from_slice(&self.keys.read_counter),
                &self.frame_hdr,
                &mut body,
                tag,
            )
        } else {
            let cipher = Eax::<Aes256>::new_from_slice(&self.keys.read_key[..32])
                .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidInput, e))?;
            cipher.decrypt_in_place_detached(
                Nonce::from_slice(&self.keys.read_counter),
                &self.frame_hdr,
                &mut body,
                tag,
            )
        };
        res.map_err(|_| {
            std::io::Error::new(std::io::ErrorKind::InvalidData, "AES-EAX auth failed")
        })?;
        increment_counter(&mut self.keys.read_counter);
        self.read_plain = body;
        self.read_pos = 0;
        self.frame_hdr_got = 0;
        self.frame_body.clear();
        self.frame_need = 0;
        self.frame_got = 0;
        Ok(())
    }
}

impl<S: AsyncRead + Unpin> AsyncRead for AesEaxIo<S> {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<std::io::Result<()>> {
        loop {
            let this = &mut *self;
            if this.read_pos < this.read_plain.len() {
                let n = std::cmp::min(buf.remaining(), this.read_plain.len() - this.read_pos);
                buf.put_slice(&this.read_plain[this.read_pos..this.read_pos + n]);
                this.read_pos += n;
                if this.read_pos >= this.read_plain.len() {
                    this.read_plain.clear();
                    this.read_pos = 0;
                }
                return Poll::Ready(Ok(()));
            }

            if this.frame_hdr_got < 2 {
                let start = this.frame_hdr_got;
                let mut tmp = [0u8; 2];
                let mut rb = ReadBuf::new(&mut tmp[start..]);
                match Pin::new(&mut this.inner).poll_read(cx, &mut rb) {
                    Poll::Ready(Ok(())) => {
                        let n = rb.filled().len();
                        if n == 0 {
                            return Poll::Ready(Ok(()));
                        }
                        this.frame_hdr[start..start + n].copy_from_slice(rb.filled());
                        this.frame_hdr_got += n;
                        if this.frame_hdr_got == 2 {
                            let length = u16::from_be_bytes(this.frame_hdr) as usize;
                            if length > MAX_MSG {
                                return Poll::Ready(Err(std::io::Error::new(
                                    std::io::ErrorKind::InvalidData,
                                    "AES-EAX frame too large",
                                )));
                            }
                            this.frame_need = length + 16;
                            this.frame_body.resize(this.frame_need, 0);
                            this.frame_got = 0;
                        }
                        continue;
                    }
                    Poll::Ready(Err(e)) => return Poll::Ready(Err(e)),
                    Poll::Pending => return Poll::Pending,
                }
            }

            let got = this.frame_got;
            let mut body = std::mem::take(&mut this.frame_body);
            if body.len() < this.frame_need {
                body.resize(this.frame_need, 0);
            }
            let mut rb = ReadBuf::new(&mut body[got..]);
            let poll = Pin::new(&mut this.inner).poll_read(cx, &mut rb);
            let n = rb.filled().len();
            this.frame_body = body;
            match poll {
                Poll::Ready(Ok(())) => {
                    if n == 0 {
                        return Poll::Ready(Err(std::io::Error::new(
                            std::io::ErrorKind::UnexpectedEof,
                            "AES-EAX truncated frame",
                        )));
                    }
                    this.frame_got += n;
                    if this.frame_got >= this.frame_need {
                        this.finish_frame()?;
                    }
                    continue;
                }
                Poll::Ready(Err(e)) => return Poll::Ready(Err(e)),
                Poll::Pending => return Poll::Pending,
            }
        }
    }
}

impl<S: AsyncWrite + Unpin> AsyncWrite for AesEaxIo<S> {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<Result<usize, std::io::Error>> {
        let this = &mut *self;
        if this.write_pending.is_empty() {
            let chunk = &buf[..std::cmp::min(buf.len(), MAX_MSG)];
            let sealed = this
                .keys
                .seal(chunk)
                .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
            this.write_pending = sealed;
            this.write_sent = 0;
            this.write_plain_report = chunk.len();
        }
        while this.write_sent < this.write_pending.len() {
            let pending = this.write_pending.clone();
            let sent = this.write_sent;
            match Pin::new(&mut this.inner).poll_write(cx, &pending[sent..]) {
                Poll::Ready(Ok(0)) => {
                    return Poll::Ready(Err(std::io::Error::new(
                        std::io::ErrorKind::WriteZero,
                        "AES-EAX write zero",
                    )));
                }
                Poll::Ready(Ok(n)) => this.write_sent += n,
                Poll::Ready(Err(e)) => return Poll::Ready(Err(e)),
                Poll::Pending => return Poll::Pending,
            }
        }
        let reported = this.write_plain_report;
        this.write_pending.clear();
        this.write_sent = 0;
        this.write_plain_report = 0;
        Poll::Ready(Ok(reported))
    }

    fn poll_flush(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Result<(), std::io::Error>> {
        Pin::new(&mut self.get_mut().inner).poll_flush(cx)
    }

    fn poll_shutdown(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
    ) -> Poll<Result<(), std::io::Error>> {
        Pin::new(&mut self.get_mut().inner).poll_shutdown(cx)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn params_for_types() {
        assert_eq!(RsaAesParams::for_sec_type(SEC_RA2).unwrap().key_bits, 128);
        assert!(RsaAesParams::for_sec_type(SEC_RA2).unwrap().all_encrypted);
        assert!(!RsaAesParams::for_sec_type(SEC_RA2NE).unwrap().all_encrypted);
        assert_eq!(
            RsaAesParams::for_sec_type(SEC_RA256).unwrap().key_bits,
            256
        );
        assert!(!RsaAesParams::for_sec_type(SEC_RANE256)
            .unwrap()
            .all_encrypted);
    }
}
