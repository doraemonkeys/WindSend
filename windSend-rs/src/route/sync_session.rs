use std::{
    io::ErrorKind,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

use tokio::{
    io::{AsyncRead, AsyncWrite, AsyncWriteExt},
    net::TcpStream,
    sync::mpsc,
};
use tokio_rustls::server::TlsStream;
use tracing::{debug, info, warn};

use crate::route::router::SessionTakeOver;
use crate::route::transfer::send_msg;
use crate::sync::{
    clipboard_domain::ClipboardPayload,
    session_registry::{AttachGrant, GLOBAL_SESSION_REGISTRY, SessionRegistryHandle},
    session_state::InboundEventDisposition,
    sync_frame::{
        AckFrame, CloseCode, CloseFrame, HeartbeatAckFrame, HeartbeatFrame, SYNC_FRAME_VERSION,
        SubscribeFrame, SubscribeRequest, SyncCapabilities, SyncFrame, SyncFrameCodecError,
        SyncFrameHead, read_frame_from_with_progress, read_frame_head_from, write_frame_head_to,
    },
};

#[cfg(test)]
use crate::sync::sync_frame::read_frame_from;

const HEARTBEAT_IDLE_THRESHOLD: Duration = Duration::from_secs(30);
const HEARTBEAT_ACK_TIMEOUT: Duration = Duration::from_secs(10);
const PEER_SILENCE_TIMEOUT: Duration = Duration::from_secs(60);

pub async fn prepare_subscription_take_over(conn: &mut TlsStream<TcpStream>) -> Result<(), ()> {
    send_transport_upgrade_ack(conn).await
}

async fn send_transport_upgrade_ack<W>(writer: &mut W) -> Result<(), ()>
where
    W: AsyncWrite + Unpin + ?Sized,
{
    // The router must finish one plain request/response cycle before the sync
    // transport takes ownership. Keeping that explicit boundary prevents later
    // session work from silently smuggling state into the ordinary router path.
    send_msg(writer, &String::new()).await
}

pub async fn handle_take_over(
    conn: TlsStream<TcpStream>,
    take_over: SessionTakeOver,
) -> Option<TlsStream<TcpStream>> {
    match take_over {
        SessionTakeOver::ClipboardSubscription => {
            if let Err(error) =
                run_clipboard_subscription_transport(conn, GLOBAL_SESSION_REGISTRY.clone()).await
            {
                warn!(?error, "clipboard sync transport ended with an error");
            }
            None
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub enum SyncSessionLoopError {
    #[error("sync session codec error: {0}")]
    Codec(#[from] SyncFrameCodecError),
    #[error("sync session io error: {0}")]
    Io(#[from] std::io::Error),
}

pub async fn run_clipboard_subscription_transport<T>(
    mut transport: T,
    registry: SessionRegistryHandle,
) -> Result<(), SyncSessionLoopError>
where
    T: AsyncRead + AsyncWrite + Unpin + Send + 'static,
{
    let local_capabilities = SyncCapabilities::v2_default();
    let initial_head = match read_frame_head_from(&mut transport).await {
        Ok(head) => head,
        Err(SyncFrameCodecError::Io(error)) if is_disconnect_error(&error) => return Ok(()),
        Err(error) => {
            best_effort_close(
                &mut transport,
                protocol_error_close(format!("failed to decode subscribe frame: {error}")),
            )
            .await;
            return Ok(());
        }
    };

    let attach_lease = match accept_attach(initial_head, &local_capabilities, &registry).await {
        Ok(attach_lease) => attach_lease,
        Err(close_frame) => {
            best_effort_close(&mut transport, close_frame).await;
            return Ok(());
        }
    };

    if let Err(error) = send_subscribe_ack(&mut transport, attach_lease.grant()).await {
        registry.rollback_attach(attach_lease.into_rollback()).await;
        return Err(error);
    }

    let attach = attach_lease.commit();
    let final_state =
        run_attached_transport_loop(transport, registry.clipboard_hub(), &attach).await;
    match final_state {
        TransportFinalState::Detached => {
            registry
                .detach(&attach.session_id, attach.attach_generation)
                .await;
        }
        TransportFinalState::Closed => {
            registry
                .close_session(&attach.session_id, attach.attach_generation)
                .await;
        }
        TransportFinalState::Replaced => {}
    }
    Ok(())
}

async fn accept_attach(
    head: SyncFrameHead,
    local_capabilities: &SyncCapabilities,
    registry: &SessionRegistryHandle,
) -> Result<crate::sync::session_registry::AttachLease, CloseFrame> {
    let subscribe = match head {
        SyncFrameHead::Subscribe(frame) => frame,
        unexpected => {
            return Err(protocol_error_close(format!(
                "expected subscribe as the first sync frame, got {}",
                unexpected.kind()
            )));
        }
    };

    validate_subscribe_frame(&subscribe, local_capabilities)?;
    let negotiated_capabilities = local_capabilities.intersection(&subscribe.capabilities);

    match subscribe.request {
        SubscribeRequest::Start(start) => registry
            .start_attach(start.session_id, negotiated_capabilities)
            .await
            .map_err(|error| error.to_close_frame()),
        SubscribeRequest::Resume(resume) => registry
            .resume_attach(resume, negotiated_capabilities)
            .await
            .map_err(|error| error.to_close_frame()),
    }
}

fn validate_subscribe_frame(
    subscribe: &SubscribeFrame,
    local_capabilities: &SyncCapabilities,
) -> Result<(), CloseFrame> {
    if subscribe.version != SYNC_FRAME_VERSION {
        return Err(CloseFrame {
            close_code: CloseCode::UnsupportedVersion,
            close_reason: Some(format!(
                "expected {SYNC_FRAME_VERSION}, got {}",
                subscribe.version
            )),
        });
    }

    let negotiated_capabilities = local_capabilities.intersection(&subscribe.capabilities);
    if !negotiated_capabilities.meets_minimum_requirements() {
        return Err(CloseFrame {
            close_code: CloseCode::UnsupportedCapabilities,
            close_reason: Some(
                "capability intersection must include textBundle with a positive maxBodyBytes"
                    .to_string(),
            ),
        });
    }

    Ok(())
}

async fn send_subscribe_ack<T>(
    transport: &mut T,
    attach: &AttachGrant,
) -> Result<(), SyncSessionLoopError>
where
    T: AsyncWrite + Unpin,
{
    write_frame_head_to(
        &SyncFrameHead::SubscribeAck(attach.subscribe_ack_frame()),
        transport,
    )
    .await?;
    transport.flush().await?;
    Ok(())
}

async fn run_attached_transport_loop<T>(
    transport: T,
    clipboard_hub: crate::sync::clipboard_event_hub::ClipboardEventHubHandle,
    attach: &AttachGrant,
) -> TransportFinalState
where
    T: AsyncRead + AsyncWrite + Unpin + Send + 'static,
{
    let (reader, writer) = tokio::io::split(transport);
    let (writer_tx, writer_rx) = mpsc::channel::<SyncFrame>(1);
    let (attach_event_tx, mut attach_event_rx) = mpsc::unbounded_channel::<AttachEvent>();
    let peer_read_progress_at = Arc::new(Mutex::new(Instant::now()));

    let reader_handle = tokio::spawn(run_reader_loop(
        reader,
        attach_event_tx.clone(),
        peer_read_progress_at.clone(),
    ));
    let writer_handle = tokio::spawn(run_writer_loop(writer, writer_rx, attach_event_tx.clone()));

    let mut generation_rx = attach.session.subscribe_generation();
    let mut heartbeat_tick = tokio::time::interval(Duration::from_secs(1));
    heartbeat_tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);

    let mut activity = TransportActivityState::new(Instant::now());
    let mut pending_close = None::<PendingClose>;

    loop {
        if let Some(close_state) = pending_close.as_mut() {
            if !close_state.close_sent {
                if let Some(close_frame) = close_state.close_frame.clone() {
                    if !activity.writer_busy {
                        if queue_frame(
                            &writer_tx,
                            SyncFrame::head_only(SyncFrameHead::Close(close_frame)).unwrap(),
                            &mut activity.writer_busy,
                        ) {
                            activity.last_non_heartbeat_activity = Instant::now();
                            close_state.close_sent = true;
                        } else {
                            pending_close = Some(PendingClose::detached());
                        }
                    }
                } else {
                    break;
                }
            } else if !activity.writer_busy {
                break;
            }
        } else if !pump_next_outbound_frame(attach, &writer_tx, &mut activity) {
            pending_close = Some(PendingClose::detached());
        }

        tokio::select! {
            maybe_event = attach_event_rx.recv() => {
                let Some(event) = maybe_event else {
                    pending_close = Some(PendingClose::detached());
                    continue;
                };

                match event {
                    AttachEvent::Inbound(frame) => {
                        activity.last_peer_activity = Instant::now();
                        match handle_inbound_frame(attach, frame, &clipboard_hub, &mut activity) {
                            Ok(Some(close_state)) => pending_close = Some(close_state),
                            Ok(None) => {}
                            Err(close_state) => pending_close = Some(close_state),
                        }
                    }
                    AttachEvent::ReadDisconnected => {
                        pending_close = Some(PendingClose::detached());
                    }
                    AttachEvent::ReadFailed(error) => {
                        pending_close = Some(PendingClose::closed_with(protocol_error_close(
                            format!("failed to decode sync frame: {error}"),
                        )));
                    }
                    AttachEvent::WriteCompleted => {
                        activity.writer_busy = false;
                    }
                    AttachEvent::WriteFailed(error) => {
                        if is_disconnect_error(&error) {
                            pending_close = Some(PendingClose::detached());
                        } else {
                            warn!(?error, "clipboard sync writer failed");
                            pending_close = Some(PendingClose::detached());
                        }
                        activity.writer_busy = false;
                    }
                }
            }
            _ = attach.session.outbound_notified(), if pending_close.is_none() => {}
            generation_change = generation_rx.changed() => {
                if generation_change.is_err() || *generation_rx.borrow() != attach.attach_generation {
                    pending_close = Some(PendingClose::replaced());
                }
            }
            _ = heartbeat_tick.tick() => {
                if pending_close.is_none() {
                    let now = Instant::now();
                    let latest_peer_activity = {
                        let progress_at = *peer_read_progress_at.lock().unwrap();
                        activity.last_peer_activity.max(progress_at)
                    };
                    activity.last_peer_activity = latest_peer_activity;
                    if now.duration_since(latest_peer_activity) >= PEER_SILENCE_TIMEOUT {
                        pending_close = Some(PendingClose::detached());
                    } else if let Some(started_at) = activity.outstanding_probe_started_at
                        && now.duration_since(started_at) >= HEARTBEAT_ACK_TIMEOUT
                    {
                        pending_close = Some(PendingClose::detached());
                    }
                }
            }
        }
    }

    drop(writer_tx);
    reader_handle.abort();
    writer_handle.abort();

    pending_close
        .unwrap_or_else(PendingClose::detached)
        .final_state
}

fn pump_next_outbound_frame(
    attach: &AttachGrant,
    writer_tx: &mpsc::Sender<SyncFrame>,
    activity: &mut TransportActivityState,
) -> bool {
    if activity.writer_busy {
        return true;
    }

    if let Some(ack_up_to) = attach.session.take_pending_ack_to_send() {
        let frame = SyncFrame::head_only(SyncFrameHead::Ack(AckFrame { ack_up_to })).unwrap();
        if !queue_frame(writer_tx, frame, &mut activity.writer_busy) {
            return false;
        }
        activity.last_non_heartbeat_activity = Instant::now();
        return true;
    }

    if activity.pending_heartbeat_ack {
        let frame =
            SyncFrame::head_only(SyncFrameHead::HeartbeatAck(HeartbeatAckFrame {})).unwrap();
        if !queue_frame(writer_tx, frame, &mut activity.writer_busy) {
            return false;
        }
        activity.pending_heartbeat_ack = false;
        return true;
    }

    if let Some(event) = attach
        .session
        .pending_outbound_events_after(activity.last_sent_event_id)
        .into_iter()
        .next()
    {
        match event.to_sync_frame() {
            Ok(frame) => {
                if !queue_frame(writer_tx, frame, &mut activity.writer_busy) {
                    return false;
                }
                activity.last_sent_event_id = event.event_id;
                activity.last_non_heartbeat_activity = Instant::now();
                return true;
            }
            Err(error) => {
                warn!(?error, "failed to encode outbound sync event frame");
                return false;
            }
        }
    }

    let now = Instant::now();
    let should_send_heartbeat = activity.outstanding_probe_started_at.is_none()
        && now.duration_since(activity.last_non_heartbeat_activity) >= HEARTBEAT_IDLE_THRESHOLD
        && now.duration_since(activity.last_probe_completed_at) >= HEARTBEAT_IDLE_THRESHOLD;
    if should_send_heartbeat {
        let frame = SyncFrame::head_only(SyncFrameHead::Heartbeat(HeartbeatFrame {})).unwrap();
        if !queue_frame(writer_tx, frame, &mut activity.writer_busy) {
            return false;
        }
        activity.outstanding_probe_started_at = Some(now);
    }

    true
}
fn handle_inbound_frame(
    attach: &AttachGrant,
    frame: SyncFrame,
    clipboard_hub: &crate::sync::clipboard_event_hub::ClipboardEventHubHandle,
    activity: &mut TransportActivityState,
) -> Result<Option<PendingClose>, PendingClose> {
    match frame.head {
        SyncFrameHead::Event(event_head) => {
            activity.last_non_heartbeat_activity = Instant::now();
            let payload = ClipboardPayload::decode_body(event_head.payload_kind, &frame.body)
                .map_err(|error| {
                    PendingClose::closed_with(protocol_error_close(format!(
                        "failed to decode clipboard payload body: {error}"
                    )))
                })?;

            match attach.session.accept_remote_event_head(
                event_head.event_id,
                event_head.payload_kind,
                frame.body.len(),
            ) {
                Ok(InboundEventDisposition::Accepted { .. }) => {
                    clipboard_hub.record_remote_apply(payload.fingerprint().suppression_keys());
                    let apply_result = crate::config::CLIPBOARD.apply_payload(&payload);
                    if !apply_result.is_success() {
                        warn!(
                            session_id = %attach.session_id,
                            event_id = event_head.event_id,
                            payload_kind = ?event_head.payload_kind,
                            ?apply_result,
                            "clipboard event was accepted but local apply failed"
                        );
                    } else {
                        debug!(
                            session_id = %attach.session_id,
                            event_id = event_head.event_id,
                            payload_kind = ?event_head.payload_kind,
                            ?apply_result,
                            "clipboard event accepted and applied"
                        );
                    }
                }
                Ok(InboundEventDisposition::Duplicate { .. }) => {}
                Err(error) => {
                    return Err(PendingClose::closed_with(protocol_error_close(
                        error.to_string(),
                    )));
                }
            }
            Ok(None)
        }
        SyncFrameHead::Ack(ack_frame) => {
            activity.last_non_heartbeat_activity = Instant::now();
            attach
                .session
                .apply_peer_ack(ack_frame.ack_up_to)
                .map_err(|error| {
                    PendingClose::closed_with(protocol_error_close(error.to_string()))
                })?;
            Ok(None)
        }
        SyncFrameHead::Heartbeat(_) => {
            activity.pending_heartbeat_ack = true;
            Ok(None)
        }
        SyncFrameHead::HeartbeatAck(_) => {
            if activity.outstanding_probe_started_at.take().is_some() {
                activity.last_probe_completed_at = Instant::now();
            }
            Ok(None)
        }
        SyncFrameHead::Close(close_frame) => {
            activity.last_non_heartbeat_activity = Instant::now();
            info!(
                session_id = %attach.session_id,
                attach_generation = attach.attach_generation,
                close_code = ?close_frame.close_code,
                "clipboard sync attach closed by peer"
            );
            Ok(Some(match close_frame.close_code {
                CloseCode::SessionReplaced => PendingClose::replaced_without_echo(),
                _ => PendingClose::closed(),
            }))
        }
        unexpected => Err(PendingClose::closed_with(protocol_error_close(format!(
            "steady-state frame {} is not valid after handshake",
            unexpected.kind()
        )))),
    }
}

async fn run_reader_loop<R>(
    mut reader: R,
    event_tx: mpsc::UnboundedSender<AttachEvent>,
    peer_read_progress_at: Arc<Mutex<Instant>>,
) where
    R: AsyncRead + Unpin + Send + 'static,
{
    loop {
        let mut on_progress = || {
            *peer_read_progress_at.lock().unwrap() = Instant::now();
        };

        match read_frame_from_with_progress(&mut reader, &mut on_progress).await {
            Ok(frame) => {
                if event_tx.send(AttachEvent::Inbound(frame)).is_err() {
                    return;
                }
            }
            Err(SyncFrameCodecError::Io(error)) if is_disconnect_error(&error) => {
                let _ = event_tx.send(AttachEvent::ReadDisconnected);
                return;
            }
            Err(error) => {
                let _ = event_tx.send(AttachEvent::ReadFailed(error));
                return;
            }
        }
    }
}

async fn run_writer_loop<W>(
    mut writer: W,
    mut rx: mpsc::Receiver<SyncFrame>,
    event_tx: mpsc::UnboundedSender<AttachEvent>,
) where
    W: AsyncWrite + Unpin + Send + 'static,
{
    while let Some(frame) = rx.recv().await {
        let write_result = match crate::sync::sync_frame::write_frame_to(&frame, &mut writer).await
        {
            Ok(()) => writer.flush().await,
            Err(error) => Err(std::io::Error::other(error.to_string())),
        };

        match write_result {
            Ok(()) => {
                if event_tx.send(AttachEvent::WriteCompleted).is_err() {
                    return;
                }
            }
            Err(error) => {
                let _ = event_tx.send(AttachEvent::WriteFailed(error));
                return;
            }
        }
    }
}

fn queue_frame(
    writer_tx: &mpsc::Sender<SyncFrame>,
    frame: SyncFrame,
    writer_busy: &mut bool,
) -> bool {
    if writer_tx.try_send(frame).is_ok() {
        *writer_busy = true;
        true
    } else {
        false
    }
}

async fn best_effort_close<T>(transport: &mut T, close_frame: CloseFrame)
where
    T: AsyncWrite + Unpin,
{
    let _ = write_frame_head_to(&SyncFrameHead::Close(close_frame), transport).await;
    let _ = transport.flush().await;
}

fn protocol_error_close(reason: String) -> CloseFrame {
    CloseFrame {
        close_code: CloseCode::ProtocolError,
        close_reason: Some(reason),
    }
}

fn is_disconnect_error(error: &std::io::Error) -> bool {
    matches!(
        error.kind(),
        ErrorKind::UnexpectedEof
            | ErrorKind::ConnectionReset
            | ErrorKind::BrokenPipe
            | ErrorKind::ConnectionAborted
            | ErrorKind::NotConnected
    )
}

#[derive(Debug)]
enum AttachEvent {
    Inbound(SyncFrame),
    ReadDisconnected,
    ReadFailed(SyncFrameCodecError),
    WriteCompleted,
    WriteFailed(std::io::Error),
}

// Keep transport liveness and send-window bookkeeping cohesive so steady-state
// changes do not fan out into another round of argument threading.
#[derive(Debug)]
struct TransportActivityState {
    last_sent_event_id: u64,
    writer_busy: bool,
    pending_heartbeat_ack: bool,
    last_non_heartbeat_activity: Instant,
    last_peer_activity: Instant,
    last_probe_completed_at: Instant,
    outstanding_probe_started_at: Option<Instant>,
}

impl TransportActivityState {
    fn new(now: Instant) -> Self {
        Self {
            last_sent_event_id: 0,
            writer_busy: false,
            pending_heartbeat_ack: false,
            last_non_heartbeat_activity: now,
            last_peer_activity: now,
            last_probe_completed_at: now,
            outstanding_probe_started_at: None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum TransportFinalState {
    Detached,
    Closed,
    Replaced,
}

#[derive(Debug, Clone)]
struct PendingClose {
    final_state: TransportFinalState,
    close_frame: Option<CloseFrame>,
    close_sent: bool,
}

impl PendingClose {
    fn detached() -> Self {
        Self {
            final_state: TransportFinalState::Detached,
            close_frame: None,
            close_sent: false,
        }
    }

    fn closed() -> Self {
        Self {
            final_state: TransportFinalState::Closed,
            close_frame: None,
            close_sent: false,
        }
    }

    fn replaced() -> Self {
        Self {
            final_state: TransportFinalState::Replaced,
            close_frame: Some(CloseFrame {
                close_code: CloseCode::SessionReplaced,
                close_reason: Some("a newer attach replaced this transport generation".to_string()),
            }),
            close_sent: false,
        }
    }

    fn replaced_without_echo() -> Self {
        Self {
            final_state: TransportFinalState::Replaced,
            close_frame: None,
            close_sent: false,
        }
    }

    fn closed_with(close_frame: CloseFrame) -> Self {
        Self {
            final_state: TransportFinalState::Closed,
            close_frame: Some(close_frame),
            close_sent: false,
        }
    }
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use serde::Deserialize;
    use tokio::{
        io::{AsyncRead, AsyncReadExt, duplex},
        time::advance,
    };

    use super::*;
    use crate::route::transfer::SUCCESS_STATUS_CODE;
    use crate::sync::{
        clipboard_domain::{
            ClipboardObservationSource, ClipboardPayload, ClipboardPayloadKind, TextBundle,
        },
        sync_frame::{
            CloseCode, EventFrame, HtmlMode, ReplayRequirements, SubscribeAccepted, SubscribeFrame,
            SubscribeRequest, SubscribeResume, SubscribeStart, SyncCapabilities, SyncFrameHead,
            write_frame_to,
        },
    };

    #[derive(Debug, Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct RouteUpgradeAck {
        code: i32,
        msg: String,
        data_type: String,
        data_len: i64,
    }

    fn capabilities(
        payload_kinds: impl IntoIterator<Item = ClipboardPayloadKind>,
    ) -> SyncCapabilities {
        SyncCapabilities::new(payload_kinds, HtmlMode::Full, 8 * 1024 * 1024)
    }

    fn subscribe_start(session_id: &str, version: u32) -> SyncFrameHead {
        SyncFrameHead::Subscribe(SubscribeFrame {
            version,
            request: SubscribeRequest::Start(SubscribeStart {
                session_id: session_id.to_string(),
            }),
            capabilities: SyncCapabilities::v2_default(),
        })
    }

    fn text_snapshot(value: &str) -> crate::sync::clipboard_domain::ClipboardSnapshot {
        crate::sync::clipboard_domain::ClipboardSnapshot::new(
            ClipboardPayload::Text(TextBundle::from_plain_text(value)),
            ClipboardObservationSource::ClipboardWatcher,
        )
    }

    fn encode_head_only_frame_bytes(head: &SyncFrameHead) -> Vec<u8> {
        let head_json = serde_json::to_vec(head).unwrap();
        let mut bytes = Vec::with_capacity(4 + head_json.len());
        bytes.extend_from_slice(&(head_json.len() as u32).to_le_bytes());
        bytes.extend_from_slice(&head_json);
        bytes
    }

    async fn read_upgrade_ack(reader: &mut (impl AsyncRead + Unpin)) -> RouteUpgradeAck {
        let mut head_len_buf = [0u8; 4];
        reader.read_exact(&mut head_len_buf).await.unwrap();
        let head_len = u32::from_le_bytes(head_len_buf) as usize;
        let mut head_buf = vec![0u8; head_len];
        reader.read_exact(&mut head_buf).await.unwrap();
        serde_json::from_slice(&head_buf).unwrap()
    }
    #[tokio::test]
    async fn transport_upgrade_ack_is_plain_ok_response() {
        let (mut client, mut server) = duplex(1024);

        send_transport_upgrade_ack(&mut server).await.unwrap();

        let response = read_upgrade_ack(&mut client).await;
        assert_eq!(response.code, SUCCESS_STATUS_CODE);
        assert_eq!(response.msg, "");
        assert_eq!(response.data_type, "text");
        assert_eq!(response.data_len, 0);
    }

    #[tokio::test]
    async fn unsupported_version_is_rejected_before_session_activation() {
        let registry = SessionRegistryHandle::new(Duration::from_secs(120));
        let (mut client, server) = duplex(4096);

        let server_task = tokio::spawn({
            let registry = registry.clone();
            async move { run_clipboard_subscription_transport(server, registry).await }
        });

        write_frame_head_to(
            &subscribe_start("session-1", SYNC_FRAME_VERSION + 1),
            &mut client,
        )
        .await
        .unwrap();

        let response = read_frame_head_from(&mut client).await.unwrap();
        assert!(matches!(
            response,
            SyncFrameHead::Close(CloseFrame {
                close_code: CloseCode::UnsupportedVersion,
                ..
            })
        ));

        server_task.await.unwrap().unwrap();
    }

    #[tokio::test]
    async fn unsupported_capabilities_are_rejected_before_session_activation() {
        let registry = SessionRegistryHandle::new(Duration::from_secs(120));
        let (mut client, server) = duplex(4096);

        let server_task = tokio::spawn({
            let registry = registry.clone();
            async move { run_clipboard_subscription_transport(server, registry).await }
        });

        write_frame_head_to(
            &SyncFrameHead::Subscribe(SubscribeFrame {
                version: SYNC_FRAME_VERSION,
                request: SubscribeRequest::Start(SubscribeStart {
                    session_id: "session-1".to_string(),
                }),
                capabilities: capabilities([ClipboardPayloadKind::ImagePng]),
            }),
            &mut client,
        )
        .await
        .unwrap();

        let response = read_frame_head_from(&mut client).await.unwrap();
        assert!(matches!(
            response,
            SyncFrameHead::Close(CloseFrame {
                close_code: CloseCode::UnsupportedCapabilities,
                ..
            })
        ));

        server_task.await.unwrap().unwrap();
    }

    #[tokio::test]
    async fn unexpected_first_frame_is_rejected_as_protocol_error() {
        let registry = SessionRegistryHandle::new(Duration::from_secs(120));
        let (mut client, server) = duplex(4096);

        let server_task = tokio::spawn({
            let registry = registry.clone();
            async move { run_clipboard_subscription_transport(server, registry).await }
        });

        write_frame_head_to(&SyncFrameHead::Ack(AckFrame { ack_up_to: 7 }), &mut client)
            .await
            .unwrap();

        let response = read_frame_head_from(&mut client).await.unwrap();
        assert!(matches!(
            response,
            SyncFrameHead::Close(CloseFrame {
                close_code: CloseCode::ProtocolError,
                ..
            })
        ));

        server_task.await.unwrap().unwrap();
    }

    #[tokio::test]
    async fn resume_after_disconnect_replays_detached_queue() {
        let registry = SessionRegistryHandle::new(Duration::from_secs(120));

        let (mut first_client, first_server) = duplex(4096);
        let first_task = tokio::spawn({
            let registry = registry.clone();
            async move { run_clipboard_subscription_transport(first_server, registry).await }
        });

        write_frame_head_to(
            &subscribe_start("session-1", SYNC_FRAME_VERSION),
            &mut first_client,
        )
        .await
        .unwrap();

        let first_ack = read_frame_head_from(&mut first_client).await.unwrap();
        let first_resume_token = match first_ack {
            SyncFrameHead::SubscribeAck(ack) => match ack.accepted {
                SubscribeAccepted::Start(accepted) => accepted.resume_token,
                accepted => panic!("unexpected accepted payload: {accepted:?}"),
            },
            head => panic!("unexpected handshake response: {head:?}"),
        };

        drop(first_client);
        first_task.await.unwrap().unwrap();

        registry
            .clipboard_hub()
            .observe_snapshot(text_snapshot("queued while detached"));
        tokio::task::yield_now().await;

        let (mut second_client, second_server) = duplex(4096);
        let second_task = tokio::spawn({
            let registry = registry.clone();
            async move { run_clipboard_subscription_transport(second_server, registry).await }
        });

        write_frame_head_to(
            &SyncFrameHead::Subscribe(SubscribeFrame {
                version: SYNC_FRAME_VERSION,
                request: SubscribeRequest::Resume(SubscribeResume {
                    session_id: "session-1".to_string(),
                    resume_token: first_resume_token.clone(),
                    resume_ack_up_to: 0,
                    replay_requirements: ReplayRequirements::default(),
                }),
                capabilities: SyncCapabilities::v2_default(),
            }),
            &mut second_client,
        )
        .await
        .unwrap();

        let second_ack = read_frame_head_from(&mut second_client).await.unwrap();
        assert!(matches!(second_ack, SyncFrameHead::SubscribeAck(_)));

        let replayed = read_frame_from(&mut second_client).await.unwrap();
        match replayed.head {
            SyncFrameHead::Event(event) => {
                assert_eq!(event.event_id, 1);
                let payload =
                    ClipboardPayload::decode_body(event.payload_kind, &replayed.body).unwrap();
                assert_eq!(
                    payload,
                    ClipboardPayload::Text(TextBundle::from_plain_text("queued while detached"))
                );
            }
            head => panic!("unexpected replay frame: {head:?}"),
        }

        write_frame_head_to(
            &SyncFrameHead::Close(CloseFrame {
                close_code: CloseCode::UserStopped,
                close_reason: None,
            }),
            &mut second_client,
        )
        .await
        .unwrap();
        second_task.await.unwrap().unwrap();
    }

    #[tokio::test]
    async fn peer_close_releases_session_instead_of_detaching() {
        let registry = SessionRegistryHandle::new(Duration::from_secs(120));
        let (mut client, server) = duplex(4096);

        let server_task = tokio::spawn({
            let registry = registry.clone();
            async move { run_clipboard_subscription_transport(server, registry).await }
        });

        write_frame_head_to(
            &subscribe_start("session-1", SYNC_FRAME_VERSION),
            &mut client,
        )
        .await
        .unwrap();
        let subscribe_ack = read_frame_head_from(&mut client).await.unwrap();
        let resume_token = match subscribe_ack {
            SyncFrameHead::SubscribeAck(ack) => match ack.accepted {
                SubscribeAccepted::Start(accepted) => accepted.resume_token,
                accepted => panic!("unexpected accepted payload: {accepted:?}"),
            },
            head => panic!("unexpected handshake response: {head:?}"),
        };

        write_frame_head_to(
            &SyncFrameHead::Close(CloseFrame {
                close_code: CloseCode::UserStopped,
                close_reason: None,
            }),
            &mut client,
        )
        .await
        .unwrap();
        server_task.await.unwrap().unwrap();

        let (mut resume_client, resume_server) = duplex(4096);
        let resume_task = tokio::spawn({
            let registry = registry.clone();
            async move { run_clipboard_subscription_transport(resume_server, registry).await }
        });

        write_frame_head_to(
            &SyncFrameHead::Subscribe(SubscribeFrame {
                version: SYNC_FRAME_VERSION,
                request: SubscribeRequest::Resume(SubscribeResume {
                    session_id: "session-1".to_string(),
                    resume_token,
                    resume_ack_up_to: 0,
                    replay_requirements: ReplayRequirements::default(),
                }),
                capabilities: SyncCapabilities::v2_default(),
            }),
            &mut resume_client,
        )
        .await
        .unwrap();

        let response = read_frame_head_from(&mut resume_client).await.unwrap();
        assert!(matches!(
            response,
            SyncFrameHead::Close(CloseFrame {
                close_code: CloseCode::SessionExpired,
                ..
            })
        ));
        resume_task.await.unwrap().unwrap();
    }

    #[tokio::test(start_paused = true)]
    async fn idle_transport_sends_single_heartbeat_probe() {
        let registry = SessionRegistryHandle::new(Duration::from_secs(120));
        let (mut client, server) = duplex(4096);

        let server_task = tokio::spawn({
            let registry = registry.clone();
            async move { run_clipboard_subscription_transport(server, registry).await }
        });

        write_frame_head_to(
            &subscribe_start("session-1", SYNC_FRAME_VERSION),
            &mut client,
        )
        .await
        .unwrap();
        let _ = read_frame_head_from(&mut client).await.unwrap();

        advance(Duration::from_secs(31)).await;
        let heartbeat = read_frame_head_from(&mut client).await.unwrap();
        assert!(matches!(heartbeat, SyncFrameHead::Heartbeat(_)));

        write_frame_head_to(
            &SyncFrameHead::HeartbeatAck(HeartbeatAckFrame {}),
            &mut client,
        )
        .await
        .unwrap();

        advance(Duration::from_secs(20)).await;

        write_frame_head_to(
            &SyncFrameHead::Close(CloseFrame {
                close_code: CloseCode::UserStopped,
                close_reason: None,
            }),
            &mut client,
        )
        .await
        .unwrap();
        server_task.await.unwrap().unwrap();
    }

    #[tokio::test]
    async fn out_of_order_event_is_rejected_with_protocol_close() {
        let registry = SessionRegistryHandle::new(Duration::from_secs(120));
        let (mut client, server) = duplex(4096);

        let server_task = tokio::spawn({
            let registry = registry.clone();
            async move { run_clipboard_subscription_transport(server, registry).await }
        });

        write_frame_head_to(
            &subscribe_start("session-1", SYNC_FRAME_VERSION),
            &mut client,
        )
        .await
        .unwrap();
        let _ = read_frame_head_from(&mut client).await.unwrap();

        let body = serde_json::to_vec(&TextBundle::from_plain_text("hello")).unwrap();
        let event = SyncFrame::new(
            SyncFrameHead::Event(EventFrame {
                event_id: 2,
                payload_kind: ClipboardPayloadKind::TextBundle,
                body_len: body.len() as u32,
            }),
            body,
        )
        .unwrap();
        write_frame_to(&event, &mut client).await.unwrap();

        let response = read_frame_head_from(&mut client).await.unwrap();
        assert!(matches!(
            response,
            SyncFrameHead::Close(CloseFrame {
                close_code: CloseCode::ProtocolError,
                ..
            })
        ));

        server_task.await.unwrap().unwrap();
    }

    #[tokio::test(start_paused = true)]
    async fn slow_partial_inbound_frame_does_not_trip_peer_silence_timeout() {
        let registry = SessionRegistryHandle::new(Duration::from_secs(120));
        let (mut client, server) = duplex(4096);

        let server_task = tokio::spawn({
            let registry = registry.clone();
            async move { run_clipboard_subscription_transport(server, registry).await }
        });

        write_frame_head_to(
            &subscribe_start("session-1", SYNC_FRAME_VERSION),
            &mut client,
        )
        .await
        .unwrap();
        let _ = read_frame_head_from(&mut client).await.unwrap();

        let close_bytes = encode_head_only_frame_bytes(&SyncFrameHead::Close(CloseFrame {
            close_code: CloseCode::UserStopped,
            close_reason: Some("slow close".to_string()),
        }));
        let first_split = close_bytes.len() / 3;
        let second_split = (close_bytes.len() * 2) / 3;

        client.write_all(&close_bytes[..first_split]).await.unwrap();
        advance(Duration::from_secs(25)).await;
        tokio::task::yield_now().await;

        client
            .write_all(&close_bytes[first_split..second_split])
            .await
            .unwrap();
        advance(Duration::from_secs(25)).await;
        tokio::task::yield_now().await;

        advance(Duration::from_secs(15)).await;
        tokio::task::yield_now().await;
        assert!(!server_task.is_finished());

        client
            .write_all(&close_bytes[second_split..])
            .await
            .unwrap();
        tokio::task::yield_now().await;

        server_task.await.unwrap().unwrap();
    }
}
