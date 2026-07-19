//! VNC Authentication (DES challenge).

use cipher::{BlockEncrypt, KeyInit};
use des::Des;

/// Reverse bits in a byte (VNC DES key quirk).
fn reverse_bits(mut b: u8) -> u8 {
    b = (b & 0xF0) >> 4 | (b & 0x0F) << 4;
    b = (b & 0xCC) >> 2 | (b & 0x33) << 2;
    b = (b & 0xAA) >> 1 | (b & 0x55) << 1;
    b
}

/// Build 8-byte DES key from VNC password (max 8 chars, bit-reversed).
pub fn password_to_des_key(password: &str) -> [u8; 8] {
    let mut key = [0u8; 8];
    let bytes = password.as_bytes();
    let n = bytes.len().min(8);
    key[..n].copy_from_slice(&bytes[..n]);
    for b in &mut key {
        *b = reverse_bits(*b);
    }
    key
}

/// Encrypt 16-byte challenge → 16-byte response.
pub fn encrypt_challenge(password: &str, challenge: &[u8; 16]) -> [u8; 16] {
    let key = password_to_des_key(password);
    let cipher = Des::new_from_slice(&key).expect("8-byte DES key");
    let mut out = [0u8; 16];
    let mut block1 = cipher::Block::<Des>::clone_from_slice(&challenge[..8]);
    cipher.encrypt_block(&mut block1);
    out[..8].copy_from_slice(block1.as_slice());
    let mut block2 = cipher::Block::<Des>::clone_from_slice(&challenge[8..]);
    cipher.encrypt_block(&mut block2);
    out[8..].copy_from_slice(block2.as_slice());
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn known_vector_empty_password_key() {
        // Empty password → all-zero key after bit reverse still zeros
        assert_eq!(password_to_des_key(""), [0u8; 8]);
    }

    #[test]
    fn encrypt_is_deterministic() {
        let challenge = [1u8, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16];
        let a = encrypt_challenge("pass", &challenge);
        let b = encrypt_challenge("pass", &challenge);
        assert_eq!(a, b);
        assert_ne!(a, challenge);
    }
}
