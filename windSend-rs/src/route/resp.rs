use crate::language::{LanguageKey, LANGUAGE_MANAGER};
use crate::route::RouteRecvHead;
use crate::route::{RouteDataType, RouteRespHead};
use tokio::io::{AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio_rustls::server::TlsStream;
use tracing::{error, trace};

pub static SUCCESS_STATUS_CODE: i32 = 200;
pub static ERROR_STATUS_CODE: i32 = 400;

pub async fn send_msg_with_body(
    conn: &mut TlsStream<TcpStream>,
    msg: &String,
    datatype: crate::route::RouteDataType,
    body: &[u8],
) -> Result<(), ()> {
    let resp = crate::route::RouteRespHead {
        code: SUCCESS_STATUS_CODE,
        msg,
        data_type: datatype,
        data_len: body.len() as i64,
    };
    let resp_buf =
        serde_json::to_vec(&resp).map_err(|e| error!("json marshal failed, err: {}", e))?;
    let head_len = resp_buf.len();
    trace!(
        "head_len: {}, head: {:?},body_len: {}",
        head_len,
        resp,
        body.len()
    );
    let head_len_buf = &(head_len as u32).to_le_bytes();
    conn.write_all(head_len_buf)
        .await
        .map_err(|e| error!("write head len failed, err: {}", e))?;
    conn.write_all(&resp_buf)
        .await
        .map_err(|e| error!("write head failed, err: {}", e))?;
    conn.write_all(body)
        .await
        .map_err(|e| error!("write body failed, err: {}", e))?;
    Ok(())
}

pub async fn send_head<'a, W>(
    writer: &'a mut W,
    head: &crate::route::RouteRespHead<'a>,
) -> Result<(), ()>
where
    W: AsyncWrite + Unpin + ?Sized,
{
    let resp_buf =
        serde_json::to_vec(head).map_err(|e| error!("json marshal failed, err: {}", e))?;
    let head_len = resp_buf.len();
    trace!("head_len: {}, head: {:?}", head_len, head);
    let head_len_buf = &(head_len as u32).to_le_bytes();
    writer
        .write_all(head_len_buf)
        .await
        .map_err(|e| error!("write head len failed, err: {}", e))?;
    writer
        .write_all(&resp_buf)
        .await
        .map_err(|e| error!("write head failed, err: {}", e))?;
    Ok(())
}

pub async fn send_msg<W>(writer: &mut W, msg: &String) -> Result<(), ()>
where
    W: AsyncWrite + Unpin + ?Sized,
{
    let resp = RouteRespHead {
        code: SUCCESS_STATUS_CODE,
        msg,
        data_type: RouteDataType::Text,
        data_len: 0,
    };
    send_head(writer, &resp).await
}

pub async fn resp_error_msg<'a, W>(writer: &'a mut W, code: i32, msg: &'a String) -> Result<(), ()>
where
    W: AsyncWrite + Unpin + ?Sized,
{
    let resp = RouteRespHead {
        code,
        msg,
        data_type: RouteDataType::Text,
        data_len: 0,
    };
    send_head(writer, &resp).await
}

pub async fn resp_common_error_msg<'a, W>(writer: &'a mut W, msg: &'a String) -> Result<(), ()>
where
    W: AsyncWrite + Unpin + ?Sized,
{
    resp_error_msg(writer, ERROR_STATUS_CODE, msg).await
}

pub async fn ping_handler(conn: &mut TlsStream<TcpStream>, head: RouteRecvHead) -> Result<(), ()> {
    let mut body_buf = vec![0u8; head.data_len as usize];
    if let Err(e) = conn.read_exact(&mut body_buf).await {
        error!("read body failed, err: {}", e);
        return Err(());
    };

    let decrypted_body = crate::config::get_cryptor()
        .and_then(|c| Ok(c.decrypt(&body_buf)?))
        .map_err(|e| format!("decrypt failed, err: {}", e));
    if let Err(e) = &decrypted_body {
        error!("{}", e);
        resp_common_error_msg(conn, e).await.ok();
        return Err(());
    }
    let decrypted_body = decrypted_body.unwrap();

    if decrypted_body != b"ping" {
        let msg = format!(
            "invalid ping data: {}",
            String::from_utf8_lossy(&decrypted_body)
        );
        let _ = resp_common_error_msg(conn, &msg).await;
        return Err(());
    }
    let resp = b"pong";
    let encrypted_resp = crate::config::get_cryptor()
        .map_err(|e| error!("get_cryptor failed, err: {}", e))?
        .encrypt(resp)
        .map_err(|e| error!("encrypt failed, err: {}", e))?;

    let verify_success = LANGUAGE_MANAGER
        .read()
        .unwrap()
        .translate(LanguageKey::VerifySuccess);
    send_msg_with_body(conn, verify_success, RouteDataType::Text, &encrypted_resp).await?;
    Ok(())
}
