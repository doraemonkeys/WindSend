use serde::{Deserialize, Serialize};
use tokio::io::AsyncReadExt;
use tokio::net::TcpStream;
use tokio_rustls::server::TlsStream;
use tracing::{debug, error, trace};

#[derive(Debug, Serialize, Deserialize, Default)]
pub enum RouteAction {
    #[default]
    Unknown,
    #[serde(rename = "ping")]
    Ping,
    #[serde(rename = "pasteText")]
    PasteText,
    #[serde(rename = "pasteFile")]
    PasteFile,
    #[serde(rename = "copy")]
    Copy,
    #[serde(rename = "download")]
    Download,
}

#[derive(Debug, Serialize, Deserialize, Default)]
pub struct RouteHead {
    pub action: RouteAction,
    #[serde(rename = "timeIp")]
    pub time_ip: String,
    #[serde(rename = "fileID")]
    pub file_id: u32,
    #[serde(rename = "fileSize")]
    pub file_size: i64,
    #[serde(rename = "path")]
    pub down_path: String,
    /// 上传文件的名称
    #[serde(rename = "name")]
    pub file_name: String,
    pub start: i64,
    pub end: i64,
    #[serde(rename = "dataLen")]
    pub data_len: i64,
    /// 操作ID
    #[serde(rename = "opID")]
    pub op_id: u32,
    /// 此次操作想要上传的文件数量
    #[serde(rename = "filesCountInThisOp")]
    pub files_count_in_this_op: i32,
}

#[derive(Debug, Serialize)]
pub struct RouteRespHead<'a> {
    pub code: i32,
    pub msg: &'a String,
    /// 客户端copy时返回的数据类型(text, image, file)
    #[serde(rename = "dataType")]
    pub data_type: RouteDataType,
    /// 如果body有数据，返回数据的长度
    #[serde(rename = "dataLen")]
    pub data_len: i64,
    pub paths: Vec<RoutePathInfo>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct RoutePathInfo {
    pub path: String,
    pub size: u64,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum RouteDataType {
    #[serde(rename = "text")]
    Text,
    #[serde(rename = "clip-image")]
    ClipImage,
    #[serde(rename = "files")]
    Files,
    #[serde(rename = "binary")]
    Binary,
}
static TIME_FORMAT: &str = "%Y-%m-%d %H:%M:%S";
static EXAMINE_TIME_STR: &str = "2023-10-10 01:45:32";
static MAX_TIME_DIFF: i64 = 10;

pub async fn main_process(mut conn: tokio_rustls::server::TlsStream<tokio::net::TcpStream>) {
    let head = common_auth(&mut conn).await;
    if head.is_err() {
        return;
    }
    let head = head.unwrap();
    debug!("head: {:?}", head);
    match head.action {
        RouteAction::Ping => {
            crate::route::paste::ping_handler(&mut conn, head)
                .await
                .ok();
        }
        RouteAction::PasteText => {
            crate::route::paste::paste_text_handler(&mut conn, head).await;
        }
        RouteAction::PasteFile => {
            crate::route::paste::paste_file_handler(&mut conn, head).await;
        }
        RouteAction::Copy => {
            crate::route::copy::copy_handler(&mut conn).await;
        }
        RouteAction::Download => {
            crate::route::copy::download_handler(&mut conn, head).await;
        }
        _ => {
            crate::route::resp::resp_error_msg(
                &mut conn,
                &format!("unknown action: {:?}", head.action),
            )
            .await
            .ok();
            error!("unknown action: {:?}", head.action);
        }
    }
    use tokio::io::AsyncWriteExt;
    conn.flush()
        .await
        .map_err(|e| error!("flush failed, err: {}", e))
        .ok();
}

pub async fn common_auth(conn: &mut TlsStream<TcpStream>) -> Result<RouteHead, ()> {
    let head_buf_size = 1024;
    let mut head_buf = vec![0u8; head_buf_size];
    // 读取json长度
    let mut head_len = [0u8; 4];
    conn.read_exact(&mut head_len)
        .await
        .map_err(|e| error!("read head len failed, err: {}", e))
        .ok();
    let head_len = i32::from_le_bytes(head_len);
    if head_len > head_buf_size as i32 || head_len <= 0 {
        error!("invalid head len: {}", head_len);
        return Err(());
    }
    trace!("head_len: {}", head_len);
    head_buf.resize(head_len as usize, 0);
    // 读取json
    conn.read_exact(&mut head_buf)
        .await
        .map_err(|e| error!("read head failed, err: {}", e))
        .ok();
    let head: RouteHead = serde_json::from_slice(&head_buf)
        .map_err(|e| error!("json unmarshal failed, err: {}", e))?;
    if head.time_ip.is_empty() {
        error!("time-ip is empty");
        return Err(());
    }
    debug!("head: {:?}", head);

    let time_and_ip_bytes =
        hex::decode(&head.time_ip).map_err(|e| error!("hex decode failed, err: {}", e))?;
    let decrypted = crate::config::get_cryptor()
        .map_err(|e| error!("get_cryptor failed, err: {}", e))?
        .decrypt(&time_and_ip_bytes);
    // .map_err(|e| error!("decrypt failed, err: {}", e))?;
    if let Err(e) = decrypted {
        let remote_ip = conn
            .get_ref()
            .0
            .peer_addr()
            .map_err(|e| error!("get peer addr failed, err: {}", e));
        match remote_ip {
            Ok(remote_ip) => {
                error!(
                    "decrypt failed, err: {}, remote_ip: {}",
                    e,
                    remote_ip.ip().to_string()
                );
            }
            Err(_) => {
                error!("get peer addr failed");
                error!("decrypt failed, err: {}", e)
            }
        }
        return Err(());
    }
    let decrypted = decrypted.unwrap();

    let time_and_ip_str =
        String::from_utf8(decrypted).map_err(|e| error!("utf8 decode failed, err: {}", e))?;
    let time_len = EXAMINE_TIME_STR.len();
    if time_and_ip_str.len() < time_len {
        error!("time-ip is too short");
        return Err(());
    }
    let time_str = &time_and_ip_str[..time_len];
    let ip = &time_and_ip_str[time_len + 1..];
    trace!("time_str: {}, ip: {}", time_str, ip);
    let t = chrono::NaiveDateTime::parse_from_str(time_str, TIME_FORMAT)
        .map_err(|e| error!("parse time failed, err: {}", e))?;
    if chrono::Utc::now()
        .signed_duration_since(t.and_utc())
        .num_seconds()
        > MAX_TIME_DIFF
    {
        error!("time expired: {}", t);
        return Err(());
    }
    let myipv4 = conn
        .get_ref()
        .0
        .local_addr()
        .map_err(|e| error!("get local addr failed, err: {}", e))?;
    trace!("ip: {}, myipv4: {}", ip, myipv4.ip());
    if ip != myipv4.ip().to_string() {
        error!("ip not match: {} != {}", ip, myipv4.ip());
        return Err(());
    }
    Ok(head)
}
