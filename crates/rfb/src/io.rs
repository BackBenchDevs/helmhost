//! Async byte helpers for RFB streams.

use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};

pub async fn read_exact<R: AsyncRead + Unpin>(r: &mut R, n: usize) -> Result<Vec<u8>, String> {
    let mut buf = vec![0u8; n];
    r.read_exact(&mut buf).await.map_err(|e| e.to_string())?;
    Ok(buf)
}

pub async fn write_all<W: AsyncWrite + Unpin>(w: &mut W, data: &[u8]) -> Result<(), String> {
    w.write_all(data).await.map_err(|e| e.to_string())?;
    Ok(())
}
