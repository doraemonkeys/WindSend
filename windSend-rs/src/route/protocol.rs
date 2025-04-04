use crate::route::transfer::resp_error_msg;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tokio::io::AsyncReadExt;
use tokio::net::TcpStream;
use tokio_rustls::server::TlsStream;
use tracing::info;
use tracing::{debug, error, trace, warn};

#[derive(Debug, Serialize, Deserialize, PartialEq)]
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
    #[serde(rename = "setRelayServer")]
    SetRelayServer,
    #[serde(rename = "endConnection")]
    EndConnection,
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
    /// The file path for upload or download.
    /// For uploads, this is the relative path to upload to.
    /// For downloads, this is the path on the server to download from.
    pub path: String,
    #[serde(rename = "uploadType")]
    /// Valid when uploading a file or folder
    #[serde(default)]
    pub upload_type: UploadType,
    pub start: i64,
    pub end: i64,
    #[serde(rename = "dataLen")]
    pub data_len: i64,
    /// The ID of this upload operation
    #[serde(rename = "opID")]
    pub op_id: u32,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct UploadOperationInfo {
    /// The total size of the file to upload for this operation
    #[serde(rename = "filesSizeInThisOp")]
    pub files_size_in_this_op: i64,

    /// The number of files to upload for this operation
    #[serde(rename = "filesCountInThisOp")]
    pub files_count_in_this_op: i32,

    /// files and dirs to upload for this operation
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(rename = "uploadPaths")]
    pub upload_paths: Option<HashMap<String, PathInfo>>,

    /// A collection of empty directories uploaded by this operation
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(rename = "emptyDirs")]
    pub empty_dirs: Option<Vec<String>>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct PathInfo {
    pub path: String,
    #[serde(default)]
    pub r#type: PathType,
    pub size: Option<i64>,
}

#[derive(Debug, Serialize)]
pub struct RouteRespHead<'a> {
    pub code: i32,
    pub msg: &'a String,
    /// only for dataTypeFiles
    #[serde(
        rename = "totalFileSize",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub total_file_size: Option<u64>,
    /// The data type returned by the client when copying (text, image, file)
    #[serde(rename = "dataType")]
    pub data_type: RouteDataType,
    /// If the body has data, return the length of the data
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
    pub type_: PathType,
    #[serde(rename = "savePath")]
    pub save_path: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum PathType {
    #[serde(rename = "dir")]
    Dir,
    #[serde(rename = "file")]
    File,
    #[serde(untagged)]
    Unknown(String),
}

#[derive(Debug, Serialize, Deserialize)]
pub enum UploadType {
    #[serde(rename = "dir")]
    Dir,
    #[serde(rename = "file")]
    File,
    #[serde(rename = "uploadInfo")]
    UploadInfo,
    #[serde(untagged)]
    Unknown(String),
}

impl std::default::Default for UploadType {
    fn default() -> Self {
        UploadType::Unknown("unknown".to_string())
    }
}

impl std::default::Default for PathType {
    fn default() -> Self {
        PathType::Unknown("unknown".to_string())
    }
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SetRelayServerReq {
    #[serde(rename = "relayServerAddress")]
    pub relay_server_address: String,
    #[serde(rename = "relaySecretKey", default)]
    pub relay_secret_key: Option<String>,
    #[serde(rename = "enableRelay", default)]
    pub enable_relay: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct MatchActionRespBody {
    #[serde(rename = "deviceName")]
    pub device_name: String,
    #[serde(rename = "secretKeyHex")]
    pub secret_key_hex: String,
    #[serde(rename = "caCertificate")]
    pub ca_certificate: String,
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

// static TIME_FORMAT: &str = "%Y-%m-%d %H:%M:%S";
pub static EXAMINE_TIME_STR: &str = "2023-10-10 01:45:32";
// static MAX_TIME_DIFF: i64 = 300;
