use std::{
    collections::{BTreeSet, VecDeque},
    sync::{Arc, Mutex},
    time::{Duration, Instant, SystemTime},
};

use tokio::sync::{Notify, watch};

use crate::sync::{
    clipboard_domain::{
        ClipboardFingerprint, ClipboardPayloadCodecError, ClipboardPayloadKind, ClipboardSnapshot,
    },
    sync_frame::{EventFrame, ReplayRequirements, SyncCapabilities, SyncFrame, SyncFrameHead},
};

pub const MAX_UNACKED_EVENTS: usize = 100;
pub const MAX_UNACKED_TOTAL_BYTES: usize = 32 * 1024 * 1024;
pub const MAX_UNACKED_IMAGE_BYTES: usize = 20 * 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SessionLifecycle {
    Attached {
        generation: u64,
    },
    Detached {
        generation: u64,
        expires_at: Instant,
    },
}

#[derive(Debug)]
struct SessionRuntime {
    state: Mutex<SessionState>,
    outbound_notify: Notify,
    generation_tx: watch::Sender<u64>,
}

#[derive(Debug, Clone)]
pub struct SessionHandle {
    inner: Arc<SessionRuntime>,
}

impl SessionHandle {
    pub fn new_started(
        session_id: String,
        resume_token: String,
        negotiated_capabilities: SyncCapabilities,
    ) -> Self {
        let (generation_tx, _) = watch::channel(1_u64);
        Self {
            inner: Arc::new(SessionRuntime {
                state: Mutex::new(SessionState::new_started(
                    session_id,
                    resume_token,
                    negotiated_capabilities,
                )),
                outbound_notify: Notify::new(),
                generation_tx,
            }),
        }
    }

    pub fn clone_state(&self) -> SessionState {
        self.inner.state.lock().unwrap().clone()
    }

    pub fn restore_state(&self, state: SessionState) {
        let generation = state.attach_generation();
        *self.inner.state.lock().unwrap() = state;
        let _ = self.inner.generation_tx.send(generation);
        self.inner.outbound_notify.notify_waiters();
    }

    pub fn session_id(&self) -> String {
        self.inner.state.lock().unwrap().session_id.clone()
    }

    pub fn resume_token(&self) -> String {
        self.inner.state.lock().unwrap().resume_token.clone()
    }

    pub fn attach_generation(&self) -> u64 {
        self.inner.state.lock().unwrap().attach_generation()
    }

    pub fn current_generation(&self) -> u64 {
        self.inner.state.lock().unwrap().attach_generation()
    }

    #[cfg(test)]
    pub fn negotiated_capabilities(&self) -> SyncCapabilities {
        self.inner
            .state
            .lock()
            .unwrap()
            .negotiated_capabilities
            .clone()
    }

    pub fn subscribe_generation(&self) -> watch::Receiver<u64> {
        self.inner.generation_tx.subscribe()
    }

    pub fn outbound_notified(&self) -> tokio::sync::futures::Notified<'_> {
        self.inner.outbound_notify.notified()
    }

    pub fn is_expired(&self, now: Instant) -> bool {
        self.inner.state.lock().unwrap().is_expired(now)
    }

    pub fn should_expire(&self, generation: u64, now: Instant) -> bool {
        self.inner
            .state
            .lock()
            .unwrap()
            .should_expire(generation, now)
    }

    pub fn resume_ack_up_to(&self) -> u64 {
        self.inner.state.lock().unwrap().accepted_remote_event_id
    }

    pub fn replay_requirements(&self) -> ReplayRequirements {
        self.inner.state.lock().unwrap().replay_requirements()
    }

    pub fn pending_outbound_events_after(&self, last_sent_event_id: u64) -> Vec<OutboundEvent> {
        self.inner
            .state
            .lock()
            .unwrap()
            .pending_outbound_events_after(last_sent_event_id)
    }

    pub fn enqueue_local_snapshot(
        &self,
        snapshot: ClipboardSnapshot,
    ) -> Result<OutboundEvent, QueueLocalEventError> {
        let queued_event = self
            .inner
            .state
            .lock()
            .unwrap()
            .enqueue_local_snapshot(snapshot)?;
        self.inner.outbound_notify.notify_waiters();
        Ok(queued_event)
    }

    pub fn apply_peer_ack(&self, ack_up_to: u64) -> Result<bool, PeerAckError> {
        self.inner.state.lock().unwrap().apply_peer_ack(ack_up_to)
    }

    pub fn accept_remote_event_head(
        &self,
        event_id: u64,
        payload_kind: ClipboardPayloadKind,
        body_len: usize,
    ) -> Result<InboundEventDisposition, InboundEventError> {
        self.inner
            .state
            .lock()
            .unwrap()
            .accept_remote_event_head(event_id, payload_kind, body_len)
    }

    pub fn take_pending_ack_to_send(&self) -> Option<u64> {
        self.inner.state.lock().unwrap().take_pending_ack_to_send()
    }

    pub fn rotate_for_resume(
        &self,
        resume_token: String,
        negotiated_capabilities: SyncCapabilities,
    ) -> u64 {
        let generation = self
            .inner
            .state
            .lock()
            .unwrap()
            .rotate_for_resume(resume_token, negotiated_capabilities);
        let _ = self.inner.generation_tx.send(generation);
        generation
    }

    pub fn mark_detached(&self, generation: u64, ttl: Duration, now: Instant) -> bool {
        self.inner
            .state
            .lock()
            .unwrap()
            .mark_detached(generation, ttl, now)
    }
}

#[derive(Debug, Clone)]
pub struct SessionState {
    session_id: String,
    resume_token: String,
    negotiated_capabilities: SyncCapabilities,
    last_peer_ack_up_to: u64,
    accepted_remote_event_id: u64,
    next_local_event_id: u64,
    attach_generation: u64,
    lifecycle: SessionLifecycle,
    pending_ack_up_to: Option<u64>,
    outbound_queue: VecDeque<OutboundEvent>,
    outbound_total_bytes: usize,
    outbound_image_bytes: usize,
}

impl SessionState {
    pub fn new_started(
        session_id: String,
        resume_token: String,
        negotiated_capabilities: SyncCapabilities,
    ) -> Self {
        Self {
            session_id,
            resume_token,
            negotiated_capabilities,
            last_peer_ack_up_to: 0,
            accepted_remote_event_id: 0,
            next_local_event_id: 1,
            attach_generation: 1,
            lifecycle: SessionLifecycle::Attached { generation: 1 },
            pending_ack_up_to: None,
            outbound_queue: VecDeque::new(),
            outbound_total_bytes: 0,
            outbound_image_bytes: 0,
        }
    }

    pub fn attach_generation(&self) -> u64 {
        self.attach_generation
    }

    pub fn replay_requirements(&self) -> ReplayRequirements {
        let payload_kinds = self
            .outbound_queue
            .iter()
            .map(|event| event.payload_kind)
            .collect::<BTreeSet<_>>();
        let max_body_bytes = self
            .outbound_queue
            .iter()
            .map(|event| event.body_len() as u32)
            .max()
            .unwrap_or(0);
        ReplayRequirements::new(payload_kinds, max_body_bytes)
    }

    pub fn is_current_generation(&self, generation: u64) -> bool {
        self.attach_generation == generation
            && matches!(
                self.lifecycle,
                SessionLifecycle::Attached {
                    generation: current_generation,
                } if current_generation == generation
            )
    }

    pub fn is_expired(&self, now: Instant) -> bool {
        matches!(
            self.lifecycle,
            SessionLifecycle::Detached { expires_at, .. } if expires_at <= now
        )
    }

    pub fn should_expire(&self, generation: u64, now: Instant) -> bool {
        matches!(
            self.lifecycle,
            SessionLifecycle::Detached {
                generation: detached_generation,
                expires_at,
            } if detached_generation == generation && expires_at <= now
        )
    }

    pub fn rotate_for_resume(
        &mut self,
        resume_token: String,
        negotiated_capabilities: SyncCapabilities,
    ) -> u64 {
        self.attach_generation += 1;
        self.resume_token = resume_token;
        self.negotiated_capabilities = negotiated_capabilities;
        self.lifecycle = SessionLifecycle::Attached {
            generation: self.attach_generation,
        };
        self.attach_generation
    }

    pub fn mark_detached(&mut self, generation: u64, ttl: Duration, now: Instant) -> bool {
        if !self.is_current_generation(generation) {
            return false;
        }

        self.lifecycle = SessionLifecycle::Detached {
            generation,
            expires_at: now + ttl,
        };
        true
    }

    pub fn pending_outbound_events_after(&self, last_sent_event_id: u64) -> Vec<OutboundEvent> {
        self.outbound_queue
            .iter()
            .filter(|event| event.event_id > last_sent_event_id)
            .cloned()
            .collect()
    }

    pub fn enqueue_local_snapshot(
        &mut self,
        snapshot: ClipboardSnapshot,
    ) -> Result<OutboundEvent, QueueLocalEventError> {
        let payload_kind = snapshot.payload.kind();
        if !self
            .negotiated_capabilities
            .supports_payload_kind(payload_kind)
        {
            return Err(QueueLocalEventError::UnsupportedPayloadKind { payload_kind });
        }

        let encoded_body = snapshot
            .payload
            .encode_body()
            .map_err(QueueLocalEventError::EncodeBody)?;
        let body_len = encoded_body.len();
        if body_len > self.negotiated_capabilities.max_body_bytes as usize {
            return Err(QueueLocalEventError::BodyTooLarge {
                body_len,
                max_body_bytes: self.negotiated_capabilities.max_body_bytes as usize,
            });
        }

        let projected_event_count = self.outbound_queue.len() + 1;
        if projected_event_count > MAX_UNACKED_EVENTS {
            return Err(QueueLocalEventError::QueueEventsExceeded {
                next_events: projected_event_count,
                max_events: MAX_UNACKED_EVENTS,
            });
        }

        let projected_total_bytes = self.outbound_total_bytes + body_len;
        if projected_total_bytes > MAX_UNACKED_TOTAL_BYTES {
            return Err(QueueLocalEventError::QueueTotalBytesExceeded {
                next_total_bytes: projected_total_bytes,
                max_total_bytes: MAX_UNACKED_TOTAL_BYTES,
            });
        }

        let projected_image_bytes = if payload_kind == ClipboardPayloadKind::ImagePng {
            self.outbound_image_bytes + body_len
        } else {
            self.outbound_image_bytes
        };
        if projected_image_bytes > MAX_UNACKED_IMAGE_BYTES {
            return Err(QueueLocalEventError::QueueImageBytesExceeded {
                next_image_bytes: projected_image_bytes,
                max_image_bytes: MAX_UNACKED_IMAGE_BYTES,
            });
        }

        let queued_event = OutboundEvent {
            session_id: self.session_id.clone(),
            event_id: self.next_local_event_id,
            payload_kind,
            body: Arc::from(encoded_body),
            fingerprint: snapshot.fingerprint(),
            created_at: snapshot.observed_at,
        };
        self.next_local_event_id += 1;
        self.outbound_total_bytes = projected_total_bytes;
        self.outbound_image_bytes = projected_image_bytes;
        self.outbound_queue.push_back(queued_event.clone());
        Ok(queued_event)
    }

    pub fn apply_peer_ack(&mut self, ack_up_to: u64) -> Result<bool, PeerAckError> {
        if ack_up_to <= self.last_peer_ack_up_to {
            return Ok(false);
        }

        let last_assigned_event_id = self.next_local_event_id.saturating_sub(1);
        if ack_up_to > last_assigned_event_id {
            return Err(PeerAckError::AckBeyondAssignedEvents {
                ack_up_to,
                last_assigned_event_id,
            });
        }

        self.last_peer_ack_up_to = ack_up_to;
        while self
            .outbound_queue
            .front()
            .is_some_and(|event| event.event_id <= ack_up_to)
        {
            let removed = self.outbound_queue.pop_front().unwrap();
            self.outbound_total_bytes =
                self.outbound_total_bytes.saturating_sub(removed.body_len());
            if removed.payload_kind == ClipboardPayloadKind::ImagePng {
                self.outbound_image_bytes =
                    self.outbound_image_bytes.saturating_sub(removed.body_len());
            }
        }

        Ok(true)
    }

    pub fn accept_remote_event_head(
        &mut self,
        event_id: u64,
        payload_kind: ClipboardPayloadKind,
        body_len: usize,
    ) -> Result<InboundEventDisposition, InboundEventError> {
        if !self
            .negotiated_capabilities
            .supports_payload_kind(payload_kind)
        {
            return Err(InboundEventError::UnsupportedPayloadKind { payload_kind });
        }

        if body_len > self.negotiated_capabilities.max_body_bytes as usize {
            return Err(InboundEventError::BodyTooLarge {
                body_len,
                max_body_bytes: self.negotiated_capabilities.max_body_bytes as usize,
            });
        }

        if event_id <= self.accepted_remote_event_id {
            self.mark_pending_ack(self.accepted_remote_event_id);
            return Ok(InboundEventDisposition::Duplicate {
                ack_up_to: self.accepted_remote_event_id,
            });
        }

        let expected_event_id = self.accepted_remote_event_id + 1;
        if event_id != expected_event_id {
            return Err(InboundEventError::OutOfOrder {
                expected_event_id,
                actual_event_id: event_id,
            });
        }

        self.accepted_remote_event_id = event_id;
        self.mark_pending_ack(event_id);
        Ok(InboundEventDisposition::Accepted {
            ack_up_to: event_id,
        })
    }

    pub fn take_pending_ack_to_send(&mut self) -> Option<u64> {
        self.pending_ack_up_to.take()
    }

    fn mark_pending_ack(&mut self, ack_up_to: u64) {
        self.pending_ack_up_to = Some(self.pending_ack_up_to.unwrap_or(0).max(ack_up_to));
    }
}

#[derive(Debug, Clone)]
pub struct OutboundEvent {
    #[allow(dead_code)]
    pub session_id: String,
    pub event_id: u64,
    pub payload_kind: ClipboardPayloadKind,
    #[allow(dead_code)]
    pub fingerprint: ClipboardFingerprint,
    #[allow(dead_code)]
    pub created_at: SystemTime,
    body: Arc<[u8]>,
}

impl OutboundEvent {
    pub fn body_len(&self) -> usize {
        self.body.len()
    }

    pub fn to_sync_frame(&self) -> Result<SyncFrame, crate::sync::sync_frame::SyncFrameCodecError> {
        SyncFrame::new(
            SyncFrameHead::Event(EventFrame {
                event_id: self.event_id,
                payload_kind: self.payload_kind,
                body_len: self.body_len() as u32,
            }),
            self.body.to_vec(),
        )
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InboundEventDisposition {
    Accepted { ack_up_to: u64 },
    Duplicate { ack_up_to: u64 },
}

#[derive(Debug, thiserror::Error)]
pub enum QueueLocalEventError {
    #[error("payload kind {payload_kind:?} is outside the negotiated capability intersection")]
    UnsupportedPayloadKind { payload_kind: ClipboardPayloadKind },
    #[error("payload body size {body_len} exceeds maxBodyBytes {max_body_bytes}")]
    BodyTooLarge {
        body_len: usize,
        max_body_bytes: usize,
    },
    #[error("queue would exceed max events: next {next_events}, limit {max_events}")]
    QueueEventsExceeded {
        next_events: usize,
        max_events: usize,
    },
    #[error("queue would exceed max total bytes: next {next_total_bytes}, limit {max_total_bytes}")]
    QueueTotalBytesExceeded {
        next_total_bytes: usize,
        max_total_bytes: usize,
    },
    #[error("queue would exceed max image bytes: next {next_image_bytes}, limit {max_image_bytes}")]
    QueueImageBytesExceeded {
        next_image_bytes: usize,
        max_image_bytes: usize,
    },
    #[error("failed to encode clipboard payload body: {0}")]
    EncodeBody(#[from] ClipboardPayloadCodecError),
}

#[derive(Debug, thiserror::Error)]
pub enum PeerAckError {
    #[error(
        "ack_up_to {ack_up_to} exceeds the largest assigned outbound event {last_assigned_event_id}"
    )]
    AckBeyondAssignedEvents {
        ack_up_to: u64,
        last_assigned_event_id: u64,
    },
}

#[derive(Debug, thiserror::Error)]
pub enum InboundEventError {
    #[error("payload kind {payload_kind:?} is outside the negotiated capability intersection")]
    UnsupportedPayloadKind { payload_kind: ClipboardPayloadKind },
    #[error("payload body size {body_len} exceeds maxBodyBytes {max_body_bytes}")]
    BodyTooLarge {
        body_len: usize,
        max_body_bytes: usize,
    },
    #[error("expected inbound event {expected_event_id}, got {actual_event_id}")]
    OutOfOrder {
        expected_event_id: u64,
        actual_event_id: u64,
    },
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sync::{
        clipboard_domain::{ClipboardPayload, TextBundle},
        sync_frame::HtmlMode,
    };

    fn capabilities(
        payload_kinds: impl IntoIterator<Item = ClipboardPayloadKind>,
        max_body_bytes: u32,
    ) -> SyncCapabilities {
        SyncCapabilities::new(payload_kinds, HtmlMode::Full, max_body_bytes)
    }

    fn text_snapshot(value: &str) -> ClipboardSnapshot {
        ClipboardSnapshot::new(
            ClipboardPayload::Text(TextBundle::from_plain_text(value)),
            crate::sync::clipboard_domain::ClipboardObservationSource::ClipboardWatcher,
        )
    }

    #[test]
    fn local_queue_assigns_event_ids_and_tracks_replay_requirements() {
        let session = SessionHandle::new_started(
            "session-1".to_string(),
            "token-1".to_string(),
            capabilities([ClipboardPayloadKind::TextBundle], 1024),
        );

        let first = session.enqueue_local_snapshot(text_snapshot("A")).unwrap();
        let second = session.enqueue_local_snapshot(text_snapshot("B")).unwrap();

        assert_eq!(first.event_id, 1);
        assert_eq!(second.event_id, 2);
        assert_eq!(
            session.replay_requirements(),
            ReplayRequirements::new([ClipboardPayloadKind::TextBundle], second.body_len() as u32)
        );
        assert_eq!(session.pending_outbound_events_after(1).len(), 1);
    }

    #[test]
    fn peer_ack_trims_queue_and_rejects_future_ack_ids() {
        let session = SessionHandle::new_started(
            "session-1".to_string(),
            "token-1".to_string(),
            capabilities([ClipboardPayloadKind::TextBundle], 1024),
        );
        session.enqueue_local_snapshot(text_snapshot("A")).unwrap();
        session.enqueue_local_snapshot(text_snapshot("B")).unwrap();

        assert!(session.apply_peer_ack(1).unwrap());
        assert_eq!(session.pending_outbound_events_after(0).len(), 1);
        assert!(matches!(
            session.apply_peer_ack(9),
            Err(PeerAckError::AckBeyondAssignedEvents {
                ack_up_to: 9,
                last_assigned_event_id: 2,
            })
        ));
    }

    #[test]
    fn inbound_events_must_arrive_in_order_and_merge_pending_ack() {
        let session = SessionHandle::new_started(
            "session-1".to_string(),
            "token-1".to_string(),
            capabilities([ClipboardPayloadKind::TextBundle], 1024),
        );

        assert!(matches!(
            session.accept_remote_event_head(1, ClipboardPayloadKind::TextBundle, 10),
            Ok(InboundEventDisposition::Accepted { ack_up_to: 1 })
        ));
        assert_eq!(session.take_pending_ack_to_send(), Some(1));

        assert!(matches!(
            session.accept_remote_event_head(1, ClipboardPayloadKind::TextBundle, 10),
            Ok(InboundEventDisposition::Duplicate { ack_up_to: 1 })
        ));
        assert_eq!(session.take_pending_ack_to_send(), Some(1));

        assert!(matches!(
            session.accept_remote_event_head(3, ClipboardPayloadKind::TextBundle, 10),
            Err(InboundEventError::OutOfOrder {
                expected_event_id: 2,
                actual_event_id: 3,
            })
        ));
    }

    #[test]
    fn resume_rotation_updates_generation_and_capabilities() {
        let session = SessionHandle::new_started(
            "session-1".to_string(),
            "token-1".to_string(),
            capabilities([ClipboardPayloadKind::TextBundle], 1024),
        );

        let next_generation = session.rotate_for_resume(
            "token-2".to_string(),
            capabilities(
                [
                    ClipboardPayloadKind::TextBundle,
                    ClipboardPayloadKind::ImagePng,
                ],
                2048,
            ),
        );

        assert_eq!(next_generation, 2);
        assert_eq!(session.attach_generation(), 2);
        assert_eq!(session.resume_token(), "token-2");
        assert!(
            session
                .negotiated_capabilities()
                .supports_payload_kind(ClipboardPayloadKind::ImagePng)
        );
    }
}
