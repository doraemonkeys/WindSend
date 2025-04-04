use crate::relay::transfer::*;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StatusCode {
    Error = 0,
    Success = -1,
    AuthFailed = 1,
}

impl Serialize for StatusCode {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        serializer.serialize_i32(*self as i32)
    }
}

impl TryFrom<i32> for StatusCode {
    type Error = String;

    fn try_from(value: i32) -> Result<Self, String> {
        match value {
            0 => Ok(StatusCode::Error),
            -1 => Ok(StatusCode::Success),
            1 => Ok(StatusCode::AuthFailed),
            _ => Err(format!("Invalid StatusCode value: {}", value)),
        }
    }
}

impl<'de> Deserialize<'de> for StatusCode {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let value = i32::deserialize(deserializer)?;
        Self::try_from(value).map_err(serde::de::Error::custom)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HandshakeReq {
    #[serde(rename = "secretKeySelector")]
    pub secret_key_selector: Option<String>,
    #[serde(rename = "authFieldB64")]
    pub auth_field_b64: Option<String>,
    #[serde(rename = "ecdhPublicKeyB64")]
    pub ecdh_public_key_b64: String,
}

impl HandshakeReq {
    pub async fn write_to<W>(&self, writer: &mut W) -> Result<(), ()>
    where
        W: tokio::io::AsyncWrite + Unpin + ?Sized,
    {
        write_head_to(self, writer, None).await
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HandshakeResp {
    #[serde(rename = "code")]
    pub code: StatusCode,
    #[serde(rename = "msg")]
    pub msg: String,
    #[serde(rename = "ecdhPublicKeyB64")]
    pub ecdh_public_key_b64: String,
}

impl HandshakeResp {
    pub async fn read_from<R>(conn: &mut R) -> Result<Self, ()>
    where
        R: tokio::io::AsyncRead + Unpin + ?Sized,
    {
        read_head_from(conn, None).await
    }
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CommonReqHead {
    #[serde(rename = "action")]
    pub action: Action,
    #[serde(rename = "dataLen")]
    pub data_len: i32,
}

impl CommonReqHead {
    pub async fn read_from<R>(
        conn: &mut R,
        cipher: Option<&crate::utils::encrypt::AesGcmCipher>,
    ) -> Result<Self, ()>
    where
        R: tokio::io::AsyncRead + Unpin + ?Sized,
    {
        read_head_from(conn, cipher).await
    }

    pub async fn write_to<W>(
        &self,
        writer: &mut W,
        cipher: Option<&crate::utils::encrypt::AesGcmCipher>,
    ) -> Result<(), ()>
    where
        W: tokio::io::AsyncWrite + Unpin + ?Sized,
    {
        write_head_to(self, writer, cipher).await
    }

    pub async fn write_with_body<W, T>(
        action: Action,
        writer: &mut W,
        cipher: Option<&crate::utils::encrypt::AesGcmCipher>,
        body: &T,
    ) -> Result<(), ()>
    where
        W: tokio::io::AsyncWrite + Unpin + ?Sized,
        T: Serialize,
    {
        use tokio::io::AsyncWriteExt;
        use tracing::error;

        let json_buf =
            serde_json::to_vec(body).map_err(|e| error!("json marshal failed, err: {}", e))?;
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
        // self.data_len = json_buf.len() as i32;
        let req_head = CommonReqHead {
            action,
            data_len: json_buf.len() as i32,
        };

        write_head_to(&req_head, writer, cipher).await?;
        writer
            .write_all(&json_buf)
            .await
            .map_err(|e| error!("write body failed, err: {}", e))?;
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CommonReq {
    #[serde(rename = "id")]
    pub id: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RespHead {
    #[serde(rename = "code")]
    pub code: StatusCode,
    #[serde(rename = "msg")]
    pub msg: String,
    #[serde(rename = "action")]
    pub action: Action,
    #[serde(rename = "dataLen")]
    pub data_len: i32,
}

impl RespHead {
    pub async fn read_from<R>(
        conn: &mut R,
        cipher: Option<&crate::utils::encrypt::AesGcmCipher>,
    ) -> Result<Self, ()>
    where
        R: tokio::io::AsyncRead + Unpin + ?Sized,
    {
        read_head_from(conn, cipher).await
    }

    pub async fn write_to<W>(
        &self,
        writer: &mut W,
        cipher: Option<&crate::utils::encrypt::AesGcmCipher>,
    ) -> Result<(), ()>
    where
        W: tokio::io::AsyncWrite + Unpin + ?Sized,
    {
        write_head_to(self, writer, cipher).await
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConnectionReq {
    #[serde(flatten)]
    pub common: CommonReq,
}

impl ConnectionReq {
    pub async fn write_to<W>(
        &self,
        writer: &mut W,
        cipher: Option<&crate::utils::encrypt::AesGcmCipher>,
    ) -> Result<(), ()>
    where
        W: tokio::io::AsyncWrite + Unpin + ?Sized,
    {
        CommonReqHead::write_with_body(Action::Connect, writer, cipher, self).await
    }
}
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Action {
    #[serde(rename = "connect")]
    Connect,
    #[serde(rename = "ping")]
    Ping,
    #[serde(rename = "relay")]
    Relay,
    #[serde(rename = "close")]
    Close,
    #[serde(rename = "heartbeat")]
    Heartbeat,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HeartbeatReq {
    #[serde(flatten)]
    pub common: CommonReq,
    #[serde(rename = "needResp")]
    pub need_resp: bool,
}

impl HeartbeatReq {
    pub async fn write_to<W>(
        &self,
        writer: &mut W,
        cipher: Option<&crate::utils::encrypt::AesGcmCipher>,
    ) -> Result<(), ()>
    where
        W: tokio::io::AsyncWrite + Unpin + ?Sized,
    {
        CommonReqHead::write_with_body(Action::Heartbeat, writer, cipher, self).await
    }

    pub async fn read_from<R>(
        conn: &mut R,
        data_len: i32,
        cipher: Option<&crate::utils::encrypt::AesGcmCipher>,
    ) -> Result<Self, ()>
    where
        R: tokio::io::AsyncRead + Unpin + ?Sized,
    {
        read_from(conn, data_len, cipher).await
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RelayReq {
    #[serde(flatten)]
    pub common: CommonReq,
}
