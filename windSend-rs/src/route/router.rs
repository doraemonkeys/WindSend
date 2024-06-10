use serde::{Deserialize, Serialize};
use tokio::io::AsyncReadExt;
use tokio::net::TcpStream;
use tokio_rustls::server::TlsStream;
use tracing::info;
use tracing::{debug, error, trace, warn};

use crate::config::GLOBAL_CONFIG;
use crate::route::resp::resp_error_msg;

#[derive(Debug, Serialize, Deserialize)]
pub enum RouteAction {
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
    #[serde(rename = "match")]
    Match,
    #[serde(rename = "syncText")]
    SyncText,
    #[serde(untagged)]
    Unknown(String),
}

impl std::default::Default for RouteAction {
    fn default() -> Self {
        RouteAction::Unknown("unknown".to_string())
    }
}

#[derive(Debug, Serialize, Deserialize, Default)]
pub struct RouteRecvHead {
    pub action: RouteAction,
    #[serde(rename = "deviceName")]
    pub device_name: String,
    #[serde(rename = "timeIp")]
    pub time_ip: String,
    #[serde(rename = "fileID")]
    pub file_id: u32,
    #[serde(rename = "fileSize")]
    pub file_size: i64,
    #[serde(rename = "path")]
    /// 上传或下载文件时的文件路径
    pub path: String,
    #[serde(rename = "uploadType")]
    /// 上传文件或文件夹时有效
    #[serde(default)]
    pub upload_type: PathInfoType,
    pub start: i64,
    pub end: i64,
    #[serde(rename = "dataLen")]
    pub data_len: i64,
    /// 此次上传操作的ID
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
    // pub paths: Vec<RoutePathInfo>,
}

#[derive(Debug, Serialize, Default)]
pub struct RouteTransferInfo {
    #[serde(rename = "path")]
    pub remote_path: String,
    pub size: u64,
    #[serde(rename = "type")]
    pub type_: PathInfoType,
    #[serde(rename = "savePath")]
    pub save_path: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum PathInfoType {
    #[serde(rename = "dir")]
    Dir,
    #[serde(rename = "file")]
    File,
    #[serde(untagged)]
    Unknown(String),
}

impl std::default::Default for PathInfoType {
    fn default() -> Self {
        PathInfoType::Unknown("unknown".to_string())
    }
}

#[derive(Debug, Serialize, Deserialize)]
struct MatchActionRespBody {
    #[serde(rename = "deviceName")]
    device_name: String,
    #[serde(rename = "secretKeyHex")]
    secret_key_hex: String,
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
static MAX_TIME_DIFF: i64 = 300;

pub async fn main_process(mut conn: tokio_rustls::server::TlsStream<tokio::net::TcpStream>) {
    loop {
        let head = common_auth(&mut conn).await;
        if head.is_err() {
            return;
        }
        let head = head.unwrap();
        info!("recv head: {:?}", head);

        let mut ok = false;
        match head.action {
            RouteAction::Ping => {
                let _ = crate::route::resp::ping_handler(&mut conn, head).await;
            }
            RouteAction::PasteText => {
                crate::route::paste::paste_text_handler(&mut conn, head).await;
            }
            RouteAction::PasteFile => {
                ok = crate::route::paste::paste_file_handler(&mut conn, head).await;
            }
            RouteAction::Copy => {
                crate::route::copy::copy_handler(&mut conn).await;
            }
            RouteAction::Download => {
                ok = crate::route::copy::download_handler(&mut conn, head).await;
            }
            RouteAction::Match => {
                let _ = match_handler(&mut conn).await;
            }
            RouteAction::SyncText => {
                crate::route::paste::sync_text_handler(&mut conn, head).await;
            }
            RouteAction::Unknown(action) => {
                let msg = format!("unknown action: {:?}", action);
                let _ = crate::route::resp::resp_common_error_msg(&mut conn, &msg).await;
                error!("{}", msg);
            }
        }
        use tokio::io::AsyncWriteExt;
        if let Err(e) = conn.flush().await {
            error!("flush failed, err: {}", e);
        }
        if !ok {
            return;
        }
    }
}

pub async fn common_auth(conn: &mut TlsStream<TcpStream>) -> Result<RouteRecvHead, ()> {
    const UNAUTHORIZED_CODE: i32 = 401;
    // 头部不能超过10KB，以防止恶意攻击导致内存溢出
    const MAX_HEAD_LEN: isize = 1024 * 10;

    let remote_ip = conn
        .get_ref()
        .0
        .peer_addr()
        .map_err(|e| error!("get peer addr failed, err: {}", e))
        .unwrap_or(std::net::SocketAddr::from(([0, 0, 0, 0], 0)));
    info!("try to read head, remote ip: {}", remote_ip);

    // 读取json长度
    let mut head_len = [0u8; 4];
    if let Err(e) = conn.read_exact(&mut head_len).await {
        match e.kind() {
            std::io::ErrorKind::UnexpectedEof => info!("client {} closed", remote_ip),
            _ => error!("read head len failed, err: {}", e),
        }
        return Err(());
    }
    let head_len = i32::from_le_bytes(head_len);
    if head_len > MAX_HEAD_LEN as i32 || head_len <= 0 {
        error!("invalid head len: {}", head_len);
        return Err(());
    }
    let mut head_buf = vec![0u8; head_len as usize];
    trace!("head_len: {}", head_len);
    // 读取json
    conn.read_exact(&mut head_buf)
        .await
        .map_err(|e| error!("read head failed, err: {}", e))?;
    debug!("head_buf: {:?}", String::from_utf8_lossy(&head_buf));
    let head: RouteRecvHead = serde_json::from_slice(&head_buf)
        .map_err(|e| error!("json unmarshal failed, err: {}", e))?;

    if let RouteAction::Match = head.action {
        if *crate::config::ALLOW_TO_BE_SEARCHED.lock().unwrap() {
            return Ok(head);
        }
        let msg = format!(
            "search not allowed, deviceName: {}, ip: {}",
            head.device_name,
            remote_ip.ip()
        );
        warn!("{}", msg);
        let _ = resp_error_msg(conn, UNAUTHORIZED_CODE, &msg).await;
        return Err(());
    }

    if head.time_ip.is_empty() {
        let msg = format!("time-ip field is empty, remote ip: {}", remote_ip.ip());
        error!(msg);
        let _ = resp_error_msg(conn, UNAUTHORIZED_CODE, &msg).await;
        return Err(());
    }
    debug!("head: {:?}", head);

    let time_and_ip_bytes =
        hex::decode(&head.time_ip).map_err(|e| error!("hex decode failed, err: {}", e))?;
    let decrypted = crate::config::get_cryptor()
        .map_err(|e| error!("get_cryptor failed, err: {}", e))?
        .decrypt(&time_and_ip_bytes);

    if let Err(e) = decrypted {
        let msg = format!("decrypt failed, err: {}, remote_ip: {}", e, remote_ip.ip());
        info!(msg);
        let _ = resp_error_msg(conn, UNAUTHORIZED_CODE, &msg).await;
        return Err(());
    }
    let decrypted = decrypted.unwrap();

    let time_and_ip_str =
        String::from_utf8(decrypted).map_err(|e| error!("utf8 decode failed, err: {}", e))?;
    let time_len = EXAMINE_TIME_STR.len();
    if time_and_ip_str.len() < time_len {
        let msg = format!("time-ip is too short, remote_ip: {}", remote_ip.ip());
        error!(msg);
        let _ = resp_error_msg(conn, UNAUTHORIZED_CODE, &msg).await;
        return Err(());
    }
    let time_str = &time_and_ip_str[..time_len];
    let ip = &time_and_ip_str[time_len + 1..];
    trace!("time_str: {}, ip: {}", time_str, ip);
    let t = chrono::NaiveDateTime::parse_from_str(time_str, TIME_FORMAT)
        .map_err(|e| error!("parse time failed, err: {}", e))?;
    let now = chrono::Utc::now();
    if now.signed_duration_since(t.and_utc()).num_seconds() > MAX_TIME_DIFF {
        let msg = format!("time expired! recv time: {}, local time: {}", t, now);
        debug!(msg);
        let _ = resp_error_msg(conn, UNAUTHORIZED_CODE, &msg).await;
        return Err(());
    }
    let myip = conn
        .get_ref()
        .0
        .local_addr()
        .map_err(|e| error!("get local addr failed, err: {}", e))?
        .ip()
        .to_string();
    debug!("ip: {}, myip: {}", ip, myip);
    let myip = myip.strip_prefix("::ffff:").unwrap_or(myip.as_str());
    let mut ip = ip;
    if ip.contains('%') {
        ip = &ip[..ip.find('%').unwrap()];
    }
    if ip != myip {
        {
            let external_ips = &GLOBAL_CONFIG.read().unwrap().external_ips;
            if !external_ips.is_none() && external_ips.as_ref().unwrap().contains(&ip.to_string()) {
                return Ok(head);
            }
        }
        let msg = format!("ip not match: {} != {}", ip, myip);
        error!(msg);
        let _ = resp_error_msg(conn, UNAUTHORIZED_CODE, &msg).await;
        return Err(());
    }
    Ok(head)
}

async fn match_handler(conn: &mut TlsStream<TcpStream>) -> Result<(), ()> {
    let hostname = hostname::get()
        .map_err(|e| error!("get hostname failed, err: {}", e))
        .unwrap_or_default();
    let hostname: String = hostname.to_string_lossy().to_string();
    let action_resp = MatchActionRespBody {
        device_name: hostname,
        secret_key_hex: crate::config::GLOBAL_CONFIG
            .read()
            .unwrap()
            .secret_key_hex
            .clone(),
    };
    let action_resp = serde_json::to_vec(&action_resp);
    if let Err(e) = &action_resp {
        let err = format!("json marshal failed, err: {}", e);
        error!("{}", err);
        let _ = crate::route::resp::resp_common_error_msg(conn, &err).await;
        return Err(());
    }
    let r =
        crate::route::resp::send_msg(conn, &String::from_utf8(action_resp.unwrap()).unwrap()).await;
    match r {
        Ok(_) => {
            #[cfg(not(feature = "disable-systray-support"))]
            let _ = crate::TX_CLOSE_QUICK_PAIR
                .get()
                .unwrap()
                .try_send(())
                .map_err(|e| error!("send close allow to be search failed, err: {}", e));
            *crate::config::ALLOW_TO_BE_SEARCHED.lock().unwrap() = false;
            info!("turn off the switch of allowing to be searched");
            Ok(())
        }
        Err(e) => Err(e),
    }
}
