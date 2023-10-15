use crate::route::{RouteDataType, RouteRespHead};
use tokio::io::{AsyncWrite, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio_rustls::server::TlsStream;
use tracing::{error, trace};

pub static SUCCESS_STATUS_CODE: i32 = 200;
pub static ERROR_STATUS_CODE: i32 = 400;

pub async fn send_msg_with_body<'a>(
    conn: &mut TlsStream<TcpStream>,
    msg: &'a String,
    datatype: crate::route::RouteDataType,
    body: &[u8],
) -> Result<(), ()> {
    let resp = crate::route::RouteRespHead {
        code: SUCCESS_STATUS_CODE,
        msg,
        data_type: datatype,
        data_len: body.len() as i64,
        paths: vec![],
    };
    let resp_buf =
        serde_json::to_vec(&resp).map_err(|e| error!("json marshal failed, err: {}", e))?;
    let head_len = resp_buf.len();
    trace!("head_len: {}, head: {:?}", head_len, resp);
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

pub async fn send_msg<'a, W>(writer: &mut W, msg: &'a String) -> Result<(), ()>
where
    W: AsyncWrite + Unpin + ?Sized,
{
    let resp = RouteRespHead {
        code: SUCCESS_STATUS_CODE,
        msg,
        data_type: RouteDataType::Text,
        data_len: 0,
        paths: vec![],
    };
    send_head(writer, &resp).await
}

pub async fn resp_error_msg<'a, W>(writer: &'a mut W, msg: &'a String) -> Result<(), ()>
where
    W: AsyncWrite + Unpin + ?Sized,
{
    let resp = RouteRespHead {
        code: ERROR_STATUS_CODE,
        msg,
        data_type: RouteDataType::Text,
        data_len: 0,
        paths: vec![],
    };
    send_head(writer, &resp).await
}
