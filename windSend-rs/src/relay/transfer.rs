use serde::{Deserialize, Serialize};
pub async fn read_head_from<R, T>(
    conn: &mut R,
    cipher: Option<&crate::utils::encrypt::AesGcmCipher>,
) -> Result<T, ()>
where
    R: tokio::io::AsyncRead + Unpin + ?Sized,
    T: for<'de> Deserialize<'de>,
{
    use tokio::io::AsyncReadExt;
    use tracing::{debug, error, trace};

    const MAX_HEAD_LEN: isize = 1024 * 10;

    // Read the length of the json
    let mut head_len = [0u8; 4];
    conn.read_exact(&mut head_len)
        .await
        .map_err(|e| error!("read CommonReqHead len failed, err: {}", e))?;
    let head_len = i32::from_le_bytes(head_len);
    if head_len > MAX_HEAD_LEN as i32 || head_len <= 0 {
        error!("invalid CommonReqHead len: {}", head_len);
        return Err(());
    }
    let mut head_buf = vec![0u8; head_len as usize];
    trace!("head_len: {}", head_len);
    // Read the json
    conn.read_exact(&mut head_buf)
        .await
        .map_err(|e| error!("read head failed, err: {}", e))?;

    let head_buf = match cipher {
        Some(cipher) => match cipher.decrypt(&mut head_buf[..], b"") {
            Ok(buf) => buf,
            Err(e) => {
                error!("decrypt head failed, err: {}", e);
                return Err(());
            }
        },
        None => &head_buf[..],
    };

    debug!("head_buf: {:?}", String::from_utf8_lossy(head_buf));

    let common_req_head: T = serde_json::from_slice(head_buf)
        .map_err(|e| error!("json unmarshal failed, err: {}", e))?;

    Ok(common_req_head)
}

pub async fn write_head_to<W, T>(
    head: &T,
    writer: &mut W,
    cipher: Option<&crate::utils::encrypt::AesGcmCipher>,
) -> Result<(), ()>
where
    W: tokio::io::AsyncWrite + Unpin + ?Sized,
    T: Serialize,
{
    use tokio::io::AsyncWriteExt;
    use tracing::error;

    let json_buf =
        serde_json::to_vec(head).map_err(|e| error!("json marshal failed, err: {}", e))?;
    let json_buf = match cipher {
        Some(cipher) => match cipher.encrypt(&json_buf, b"") {
            Ok(buf) => buf,
            Err(e) => {
                error!("encrypt failed, err: {}", e);
                return Err(());
            }
        },
        None => json_buf,
    };

    let head_len = json_buf.len();
    let head_len_buf = &(head_len as u32).to_le_bytes();
    writer
        .write_all(head_len_buf)
        .await
        .map_err(|e| error!("write head len failed, err: {}", e))?;
    writer
        .write_all(&json_buf)
        .await
        .map_err(|e| error!("write head failed, err: {}", e))?;
    Ok(())
}

pub async fn read_from<R, T>(
    conn: &mut R,
    data_len: i32,
    cipher: Option<&crate::utils::encrypt::AesGcmCipher>,
) -> Result<T, ()>
where
    R: tokio::io::AsyncRead + Unpin + ?Sized,
    T: for<'de> Deserialize<'de>,
{
    use tokio::io::AsyncReadExt;
    use tracing::error;

    let mut buf = vec![0u8; data_len as usize];
    conn.read_exact(&mut buf)
        .await
        .map_err(|e| error!("read data failed, err: {}", e))?;
    let buf = match cipher {
        Some(cipher) => match cipher.decrypt(&mut buf[..], b"") {
            Ok(buf) => buf,
            Err(e) => {
                error!("decrypt failed, err: {}", e);
                return Err(());
            }
        },
        None => &buf[..],
    };

    let data: T =
        serde_json::from_slice(buf).map_err(|e| error!("json unmarshal failed, err: {}", e))?;
    Ok(data)
}
