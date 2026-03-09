use crate::sync::clipboard_domain::ClipboardPayloadKind;
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};

pub const SYNC_FRAME_VERSION: u32 = 1;
pub const DEFAULT_SYNC_MAX_BODY_BYTES: u32 = 8 * 1024 * 1024;
pub const MAX_SYNC_FRAME_HEAD_LEN: u32 = 16 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum HtmlMode {
    Full,
    PlainTextFallback,
}

impl HtmlMode {
    pub fn intersect(self, other: Self) -> Self {
        match (self, other) {
            (Self::Full, Self::Full) => Self::Full,
            _ => Self::PlainTextFallback,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum CloseCode {
    Normal,
    UserStopped,
    SessionReplaced,
    SessionExpired,
    ResumeRejected,
    ServerShutdown,
    ProtocolError,
    UnsupportedVersion,
    UnsupportedCapabilities,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct SyncCapabilities {
    pub payload_kinds: BTreeSet<ClipboardPayloadKind>,
    pub html_mode: HtmlMode,
    pub max_body_bytes: u32,
}

impl SyncCapabilities {
    pub fn new(
        payload_kinds: impl IntoIterator<Item = ClipboardPayloadKind>,
        html_mode: HtmlMode,
        max_body_bytes: u32,
    ) -> Self {
        Self {
            payload_kinds: payload_kinds.into_iter().collect(),
            html_mode,
            max_body_bytes,
        }
    }

    pub fn v2_default() -> Self {
        Self::new(
            [
                ClipboardPayloadKind::TextBundle,
                ClipboardPayloadKind::ImagePng,
            ],
            HtmlMode::Full,
            DEFAULT_SYNC_MAX_BODY_BYTES,
        )
    }

    pub fn intersection(&self, other: &Self) -> Self {
        let payload_kinds = self
            .payload_kinds
            .intersection(&other.payload_kinds)
            .copied()
            .collect();
        Self {
            payload_kinds,
            html_mode: self.html_mode.intersect(other.html_mode),
            max_body_bytes: self.max_body_bytes.min(other.max_body_bytes),
        }
    }

    pub fn supports_payload_kind(&self, payload_kind: ClipboardPayloadKind) -> bool {
        self.payload_kinds.contains(&payload_kind)
    }

    pub fn meets_minimum_requirements(&self) -> bool {
        self.max_body_bytes > 0 && self.supports_payload_kind(ClipboardPayloadKind::TextBundle)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct ReplayRequirements {
    pub payload_kinds: BTreeSet<ClipboardPayloadKind>,
    pub max_body_bytes: u32,
}

impl ReplayRequirements {
    pub fn new(
        payload_kinds: impl IntoIterator<Item = ClipboardPayloadKind>,
        max_body_bytes: u32,
    ) -> Self {
        Self {
            payload_kinds: payload_kinds.into_iter().collect(),
            max_body_bytes,
        }
    }

    pub fn is_covered_by(&self, capabilities: &SyncCapabilities) -> bool {
        self.payload_kinds
            .iter()
            .all(|payload_kind| capabilities.supports_payload_kind(*payload_kind))
            && self.max_body_bytes <= capabilities.max_body_bytes
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum SubscribeRequest {
    Start(SubscribeStart),
    Resume(SubscribeResume),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct SubscribeStart {
    pub session_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct SubscribeResume {
    pub session_id: String,
    pub resume_token: String,
    pub resume_ack_up_to: u64,
    pub replay_requirements: ReplayRequirements,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum SubscribeAccepted {
    Start(SubscribeAcceptedStart),
    Resume(SubscribeAcceptedResume),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct SubscribeAcceptedStart {
    pub resume_token: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct SubscribeAcceptedResume {
    pub resume_token: String,
    pub resume_ack_up_to: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct SubscribeFrame {
    pub version: u32,
    pub request: SubscribeRequest,
    pub capabilities: SyncCapabilities,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct SubscribeAckFrame {
    pub version: u32,
    pub session_id: String,
    pub accepted: SubscribeAccepted,
    pub capabilities: SyncCapabilities,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct EventFrame {
    pub event_id: u64,
    pub payload_kind: ClipboardPayloadKind,
    pub body_len: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct AckFrame {
    pub ack_up_to: u64,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct HeartbeatFrame {}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct HeartbeatAckFrame {}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct CloseFrame {
    pub close_code: CloseCode,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub close_reason: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum SyncFrameHead {
    Subscribe(SubscribeFrame),
    SubscribeAck(SubscribeAckFrame),
    Event(EventFrame),
    Ack(AckFrame),
    Heartbeat(HeartbeatFrame),
    HeartbeatAck(HeartbeatAckFrame),
    Close(CloseFrame),
}

impl SyncFrameHead {
    pub fn body_len(&self) -> usize {
        match self {
            Self::Event(frame) => frame.body_len as usize,
            _ => 0,
        }
    }

    pub fn kind(&self) -> &'static str {
        match self {
            Self::Subscribe(_) => "subscribe",
            Self::SubscribeAck(_) => "subscribeAck",
            Self::Event(_) => "event",
            Self::Ack(_) => "ack",
            Self::Heartbeat(_) => "heartbeat",
            Self::HeartbeatAck(_) => "heartbeatAck",
            Self::Close(_) => "close",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SyncFrame {
    pub head: SyncFrameHead,
    pub body: Vec<u8>,
}

impl SyncFrame {
    pub fn new(head: SyncFrameHead, body: Vec<u8>) -> Result<Self, SyncFrameCodecError> {
        let expected_body_len = head.body_len();
        if body.len() != expected_body_len {
            return Err(SyncFrameCodecError::BodyLengthMismatch {
                kind: head.kind(),
                declared: expected_body_len,
                actual: body.len(),
            });
        }

        Ok(Self { head, body })
    }

    pub fn head_only(head: SyncFrameHead) -> Result<Self, SyncFrameCodecError> {
        Self::new(head, Vec::new())
    }
}

#[derive(Debug, thiserror::Error)]
pub enum SyncFrameCodecError {
    #[error("sync frame head length {head_len} exceeds limit {max_head_len}")]
    HeadTooLarge { head_len: u32, max_head_len: u32 },
    #[error("sync frame head length must be positive")]
    EmptyHead,
    #[error(
        "sync frame body length mismatch for {kind}: declared {declared} bytes, actual {actual} bytes"
    )]
    BodyLengthMismatch {
        kind: &'static str,
        declared: usize,
        actual: usize,
    },
    #[error("sync frame JSON error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("sync frame IO error: {0}")]
    Io(#[from] std::io::Error),
}

pub async fn write_frame_head_to<W>(
    head: &SyncFrameHead,
    writer: &mut W,
) -> Result<(), SyncFrameCodecError>
where
    W: AsyncWrite + Unpin + ?Sized,
{
    // The sync session deliberately reuses the repo's existing length-prefixed framing
    // so later work can focus on protocol semantics instead of inventing new byte boundaries.
    let head_json = serde_json::to_vec(head)?;
    let head_len =
        u32::try_from(head_json.len()).map_err(|_| SyncFrameCodecError::HeadTooLarge {
            head_len: u32::MAX,
            max_head_len: MAX_SYNC_FRAME_HEAD_LEN,
        })?;
    if head_len == 0 {
        return Err(SyncFrameCodecError::EmptyHead);
    }
    if head_len > MAX_SYNC_FRAME_HEAD_LEN {
        return Err(SyncFrameCodecError::HeadTooLarge {
            head_len,
            max_head_len: MAX_SYNC_FRAME_HEAD_LEN,
        });
    }

    writer.write_all(&head_len.to_le_bytes()).await?;
    writer.write_all(&head_json).await?;
    Ok(())
}

pub async fn read_frame_head_from<R>(reader: &mut R) -> Result<SyncFrameHead, SyncFrameCodecError>
where
    R: AsyncRead + Unpin + ?Sized,
{
    read_frame_head_from_with_progress(reader, &mut || {}).await
}

pub async fn read_frame_head_from_with_progress<R, F>(
    reader: &mut R,
    on_progress: &mut F,
) -> Result<SyncFrameHead, SyncFrameCodecError>
where
    R: AsyncRead + Unpin + ?Sized,
    F: FnMut(),
{
    let mut head_len_buf = [0u8; 4];
    read_exact_with_progress(reader, &mut head_len_buf, on_progress).await?;
    let head_len = u32::from_le_bytes(head_len_buf);
    if head_len == 0 {
        return Err(SyncFrameCodecError::EmptyHead);
    }
    if head_len > MAX_SYNC_FRAME_HEAD_LEN {
        return Err(SyncFrameCodecError::HeadTooLarge {
            head_len,
            max_head_len: MAX_SYNC_FRAME_HEAD_LEN,
        });
    }

    let mut head_buf = vec![0u8; head_len as usize];
    read_exact_with_progress(reader, &mut head_buf, on_progress).await?;
    Ok(serde_json::from_slice(&head_buf)?)
}

pub async fn write_frame_to<W>(frame: &SyncFrame, writer: &mut W) -> Result<(), SyncFrameCodecError>
where
    W: AsyncWrite + Unpin + ?Sized,
{
    write_frame_head_to(&frame.head, writer).await?;
    if !frame.body.is_empty() {
        writer.write_all(&frame.body).await?;
    }
    Ok(())
}

#[cfg(test)]
pub async fn read_frame_from<R>(reader: &mut R) -> Result<SyncFrame, SyncFrameCodecError>
where
    R: AsyncRead + Unpin + ?Sized,
{
    read_frame_from_with_progress(reader, &mut || {}).await
}

pub async fn read_frame_from_with_progress<R, F>(
    reader: &mut R,
    on_progress: &mut F,
) -> Result<SyncFrame, SyncFrameCodecError>
where
    R: AsyncRead + Unpin + ?Sized,
    F: FnMut(),
{
    let head = read_frame_head_from_with_progress(reader, on_progress).await?;
    let mut body = vec![0u8; head.body_len()];
    if !body.is_empty() {
        read_exact_with_progress(reader, &mut body, on_progress).await?;
    }
    SyncFrame::new(head, body)
}

async fn read_exact_with_progress<R, F>(
    reader: &mut R,
    mut buf: &mut [u8],
    on_progress: &mut F,
) -> Result<(), std::io::Error>
where
    R: AsyncRead + Unpin + ?Sized,
    F: FnMut(),
{
    while !buf.is_empty() {
        let read = reader.read(buf).await?;
        if read == 0 {
            return Err(std::io::Error::from(std::io::ErrorKind::UnexpectedEof));
        }
        on_progress();
        let (_, rest) = buf.split_at_mut(read);
        buf = rest;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn capabilities(
        payload_kinds: impl IntoIterator<Item = ClipboardPayloadKind>,
        html_mode: HtmlMode,
        max_body_bytes: u32,
    ) -> SyncCapabilities {
        SyncCapabilities::new(payload_kinds, html_mode, max_body_bytes)
    }

    #[test]
    fn capabilities_intersection_keeps_shared_payloads_and_most_restrictive_limits() {
        let left = capabilities(
            [
                ClipboardPayloadKind::TextBundle,
                ClipboardPayloadKind::ImagePng,
            ],
            HtmlMode::Full,
            8 * 1024 * 1024,
        );
        let right = capabilities(
            [ClipboardPayloadKind::TextBundle],
            HtmlMode::PlainTextFallback,
            512,
        );

        let intersection = left.intersection(&right);

        assert_eq!(
            intersection.payload_kinds,
            BTreeSet::from([ClipboardPayloadKind::TextBundle])
        );
        assert_eq!(intersection.html_mode, HtmlMode::PlainTextFallback);
        assert_eq!(intersection.max_body_bytes, 512);
        assert!(intersection.meets_minimum_requirements());
    }

    #[test]
    fn replay_requirements_require_subset_of_capabilities_and_body_limit() {
        let capabilities = capabilities(
            [
                ClipboardPayloadKind::TextBundle,
                ClipboardPayloadKind::ImagePng,
            ],
            HtmlMode::Full,
            4096,
        );
        let valid = ReplayRequirements::new([ClipboardPayloadKind::TextBundle], 1024);
        let unsupported_kind = ReplayRequirements::new([ClipboardPayloadKind::ImagePng], 8192);

        assert!(valid.is_covered_by(&capabilities));
        assert!(!unsupported_kind.is_covered_by(&capabilities));
    }

    #[test]
    fn nested_union_rejects_unknown_resume_only_fields_on_start_request() {
        let invalid = serde_json::json!({
            "kind": "subscribe",
            "version": SYNC_FRAME_VERSION,
            "request": {
                "kind": "start",
                "sessionId": "session-1",
                "resumeToken": "should-not-be-here"
            },
            "capabilities": {
                "payloadKinds": ["textBundle"],
                "htmlMode": "full",
                "maxBodyBytes": 1024
            }
        });

        let parsed = serde_json::from_value::<SyncFrameHead>(invalid);
        assert!(parsed.is_err());
    }

    #[test]
    fn zero_field_heartbeat_variant_rejects_spurious_fields() {
        let invalid = serde_json::json!({
            "kind": "heartbeat",
            "eventId": 42
        });

        let parsed = serde_json::from_value::<SyncFrameHead>(invalid);
        assert!(parsed.is_err());
    }

    #[test]
    fn sync_frame_rejects_non_empty_body_for_control_frame() {
        let frame = SyncFrame::new(SyncFrameHead::Ack(AckFrame { ack_up_to: 9 }), vec![1, 2, 3]);

        assert!(matches!(
            frame,
            Err(SyncFrameCodecError::BodyLengthMismatch {
                kind: "ack",
                declared: 0,
                actual: 3,
            })
        ));
    }

    #[tokio::test]
    async fn event_frame_round_trips_through_length_prefixed_codec() {
        let head = SyncFrameHead::Event(EventFrame {
            event_id: 7,
            payload_kind: ClipboardPayloadKind::TextBundle,
            body_len: 5,
        });
        let frame = SyncFrame::new(head.clone(), b"hello".to_vec()).unwrap();

        let (mut writer, mut reader) = tokio::io::duplex(1024);
        write_frame_to(&frame, &mut writer).await.unwrap();
        drop(writer);

        let decoded = read_frame_from(&mut reader).await.unwrap();
        assert_eq!(decoded, frame);
        assert_eq!(decoded.head, head);
    }

    #[tokio::test]
    async fn head_only_frame_round_trips_without_body() {
        let head = SyncFrameHead::Close(CloseFrame {
            close_code: CloseCode::UnsupportedVersion,
            close_reason: Some("expected 1, got 2".to_string()),
        });

        let (mut writer, mut reader) = tokio::io::duplex(1024);
        write_frame_head_to(&head, &mut writer).await.unwrap();
        drop(writer);

        let decoded = read_frame_head_from(&mut reader).await.unwrap();
        assert_eq!(decoded, head);
    }
}
