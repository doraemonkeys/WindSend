use std::{
    collections::HashMap,
    sync::{Arc, LazyLock},
    time::{Duration, Instant},
};

use hex::encode;
use rand::RngExt;
use tokio::{sync::RwLock, task::JoinHandle};
use tracing::warn;

use crate::sync::{
    clipboard_domain::ClipboardSnapshot,
    clipboard_event_hub::{ClipboardEventHubHandle, GLOBAL_CLIPBOARD_EVENT_HUB},
    session_state::{PeerAckError, SessionHandle},
    sync_frame::{
        CloseCode, CloseFrame, SYNC_FRAME_VERSION, SubscribeAccepted, SubscribeAcceptedResume,
        SubscribeAcceptedStart, SubscribeAckFrame, SubscribeResume, SyncCapabilities,
    },
};

pub const DEFAULT_DETACHED_SESSION_TTL: Duration = Duration::from_secs(120);

pub static GLOBAL_SESSION_REGISTRY: LazyLock<SessionRegistryHandle> = LazyLock::new(|| {
    SessionRegistryHandle::with_hub(
        DEFAULT_DETACHED_SESSION_TTL,
        GLOBAL_CLIPBOARD_EVENT_HUB.clone(),
    )
});

#[derive(Clone)]
pub struct SessionRegistryHandle {
    inner: Arc<RwLock<SessionRegistry>>,
    clipboard_hub: ClipboardEventHubHandle,
}

impl SessionRegistryHandle {
    #[cfg(test)]
    pub fn new(session_ttl: Duration) -> Self {
        Self::with_hub(session_ttl, ClipboardEventHubHandle::new())
    }

    pub fn with_hub(session_ttl: Duration, clipboard_hub: ClipboardEventHubHandle) -> Self {
        Self {
            inner: Arc::new(RwLock::new(SessionRegistry::new(session_ttl))),
            clipboard_hub,
        }
    }

    pub fn clipboard_hub(&self) -> ClipboardEventHubHandle {
        self.clipboard_hub.clone()
    }

    pub async fn start_attach(
        &self,
        session_id: String,
        negotiated_capabilities: SyncCapabilities,
    ) -> Result<AttachLease, SessionAttachError> {
        let mut registry = self.inner.write().await;
        registry.cleanup_expired(Instant::now(), &self.clipboard_hub);

        if session_id.trim().is_empty() {
            return Err(SessionAttachError::ProtocolError(
                "session_id must not be empty".to_string(),
            ));
        }

        if registry.sessions.contains_key(&session_id) {
            return Err(SessionAttachError::ProtocolError(format!(
                "session_id {session_id} already exists; reconnects must use resume"
            )));
        }

        let resume_token = generate_resume_token();
        let session = SessionHandle::new_started(
            session_id.clone(),
            resume_token.clone(),
            negotiated_capabilities.clone(),
        );
        let receiver = self.clipboard_hub.attach_session(session_id.clone());
        let subscription_task = spawn_session_subscription(session.clone(), receiver);

        let attach_generation = session.attach_generation();
        registry.sessions.insert(
            session_id.clone(),
            SessionRecord {
                session: session.clone(),
                subscription_task,
            },
        );

        let grant = AttachGrant {
            session_id: session_id.clone(),
            attach_generation,
            accepted: SubscribeAccepted::Start(SubscribeAcceptedStart {
                resume_token: resume_token.clone(),
            }),
            capabilities: negotiated_capabilities,
            session,
        };

        Ok(AttachLease {
            grant,
            rollback: AttachRollback::RemoveStartedSession {
                session_id,
                expected_generation: attach_generation,
                expected_resume_token: resume_token,
            },
        })
    }

    pub async fn resume_attach(
        &self,
        request: SubscribeResume,
        negotiated_capabilities: SyncCapabilities,
    ) -> Result<AttachLease, SessionAttachError> {
        let now = Instant::now();
        let mut registry = self.inner.write().await;
        registry.cleanup_expired(now, &self.clipboard_hub);

        let Some(record) = registry.sessions.get(&request.session_id) else {
            return Err(SessionAttachError::SessionExpired {
                session_id: request.session_id,
                reason: "session not found".to_string(),
            });
        };

        if record.session.is_expired(now) {
            let session_id = request.session_id.clone();
            registry.remove_session(&session_id, &self.clipboard_hub);
            return Err(SessionAttachError::SessionExpired {
                session_id,
                reason: "session ttl expired".to_string(),
            });
        }

        if request.resume_token.trim().is_empty() {
            return Err(SessionAttachError::ResumeRejected {
                session_id: request.session_id,
                reason: "resume_token must not be empty".to_string(),
            });
        }

        let session = record.session.clone();
        if session.resume_token() != request.resume_token {
            return Err(SessionAttachError::ResumeRejected {
                session_id: request.session_id,
                reason: "resume token mismatch".to_string(),
            });
        }

        if !request
            .replay_requirements
            .is_covered_by(&negotiated_capabilities)
        {
            return Err(SessionAttachError::UnsupportedCapabilities {
                session_id: request.session_id,
                reason: "accepted capabilities cannot cover the retained replay requirements"
                    .to_string(),
            });
        }

        let previous_state = session.clone_state();
        if let Err(error) = session.apply_peer_ack(request.resume_ack_up_to) {
            return Err(SessionAttachError::ResumeRejected {
                session_id: request.session_id,
                reason: resume_ack_error_reason(&error),
            });
        }

        if !session
            .replay_requirements()
            .is_covered_by(&negotiated_capabilities)
        {
            session.restore_state(previous_state.clone());
            return Err(SessionAttachError::UnsupportedCapabilities {
                session_id: request.session_id,
                reason: "accepted capabilities cannot cover the retained outbound replay queue"
                    .to_string(),
            });
        }

        let next_resume_token = generate_resume_token();
        let attach_generation =
            session.rotate_for_resume(next_resume_token.clone(), negotiated_capabilities.clone());
        let resume_ack_up_to = session.resume_ack_up_to();

        let grant = AttachGrant {
            session_id: request.session_id.clone(),
            attach_generation,
            accepted: SubscribeAccepted::Resume(SubscribeAcceptedResume {
                resume_token: next_resume_token.clone(),
                resume_ack_up_to,
            }),
            capabilities: negotiated_capabilities,
            session,
        };

        Ok(AttachLease {
            grant,
            rollback: AttachRollback::RestoreResumedSession {
                session_id: request.session_id,
                expected_generation: attach_generation,
                expected_resume_token: next_resume_token,
                previous_state,
            },
        })
    }

    pub async fn rollback_attach(&self, rollback: AttachRollback) {
        let mut registry = self.inner.write().await;
        registry.rollback_attach(rollback, &self.clipboard_hub);
    }

    pub async fn detach(&self, session_id: &str, generation: u64) {
        let mut registry = self.inner.write().await;
        let now = Instant::now();
        let detached = registry.sessions.get(session_id).is_some_and(|record| {
            record
                .session
                .mark_detached(generation, registry.session_ttl, now)
        });

        if detached {
            let session_id = session_id.to_string();
            let ttl = registry.session_ttl;
            let this = self.clone();
            tokio::spawn(async move {
                tokio::time::sleep(ttl).await;
                this.expire_detached_session(session_id, generation).await;
            });
        }

        registry.cleanup_expired(now, &self.clipboard_hub);
    }

    pub async fn close_session(&self, session_id: &str, generation: u64) {
        let mut registry = self.inner.write().await;
        let should_remove = registry
            .sessions
            .get(session_id)
            .is_some_and(|record| record.session.current_generation() == generation);
        if should_remove {
            registry.remove_session(session_id, &self.clipboard_hub);
        }
    }

    async fn expire_detached_session(&self, session_id: String, generation: u64) {
        let mut registry = self.inner.write().await;
        let now = Instant::now();
        let should_remove = registry
            .sessions
            .get(&session_id)
            .is_some_and(|record| record.session.should_expire(generation, now));
        if should_remove {
            registry.remove_session(&session_id, &self.clipboard_hub);
        }
        registry.cleanup_expired(now, &self.clipboard_hub);
    }
}

#[derive(Debug)]
struct SessionRegistry {
    session_ttl: Duration,
    sessions: HashMap<String, SessionRecord>,
}

impl SessionRegistry {
    fn new(session_ttl: Duration) -> Self {
        Self {
            session_ttl,
            sessions: HashMap::new(),
        }
    }

    fn rollback_attach(
        &mut self,
        rollback: AttachRollback,
        clipboard_hub: &ClipboardEventHubHandle,
    ) {
        match rollback {
            AttachRollback::RemoveStartedSession {
                session_id,
                expected_generation,
                expected_resume_token,
            } => {
                let should_remove = self.sessions.get(&session_id).is_some_and(|record| {
                    record.session.current_generation() == expected_generation
                        && record.session.resume_token() == expected_resume_token
                });
                if should_remove {
                    self.remove_session(&session_id, clipboard_hub);
                }
            }
            AttachRollback::RestoreResumedSession {
                session_id,
                expected_generation,
                expected_resume_token,
                previous_state,
            } => {
                if let Some(record) = self.sessions.get(&session_id)
                    && record.session.current_generation() == expected_generation
                    && record.session.resume_token() == expected_resume_token
                {
                    record.session.restore_state(previous_state);
                }
            }
        }
    }

    fn cleanup_expired(&mut self, now: Instant, clipboard_hub: &ClipboardEventHubHandle) {
        let expired_sessions = self
            .sessions
            .iter()
            .filter_map(|(session_id, record)| {
                record.session.is_expired(now).then_some(session_id.clone())
            })
            .collect::<Vec<_>>();

        for session_id in expired_sessions {
            self.remove_session(&session_id, clipboard_hub);
        }
    }

    fn remove_session(&mut self, session_id: &str, clipboard_hub: &ClipboardEventHubHandle) {
        if let Some(record) = self.sessions.remove(session_id) {
            clipboard_hub.detach_session(session_id);
            record.subscription_task.abort();
        }
    }
}

#[derive(Debug)]
struct SessionRecord {
    session: SessionHandle,
    subscription_task: JoinHandle<()>,
}

fn spawn_session_subscription(
    session: SessionHandle,
    mut receiver: tokio::sync::mpsc::UnboundedReceiver<ClipboardSnapshot>,
) -> JoinHandle<()> {
    tokio::spawn(async move {
        while let Some(snapshot) = receiver.recv().await {
            if let Err(error) = session.enqueue_local_snapshot(snapshot) {
                warn!(
                    session_id = %session.session_id(),
                    ?error,
                    "clipboard event dropped because the session queue rejected it"
                );
            }
        }
    })
}

#[derive(Debug, Clone)]
pub struct AttachGrant {
    pub session_id: String,
    pub attach_generation: u64,
    pub accepted: SubscribeAccepted,
    pub capabilities: SyncCapabilities,
    pub session: SessionHandle,
}

impl AttachGrant {
    pub fn subscribe_ack_frame(&self) -> SubscribeAckFrame {
        SubscribeAckFrame {
            version: SYNC_FRAME_VERSION,
            session_id: self.session_id.clone(),
            accepted: self.accepted.clone(),
            capabilities: self.capabilities.clone(),
        }
    }
}

#[derive(Debug, Clone)]
pub struct AttachLease {
    grant: AttachGrant,
    rollback: AttachRollback,
}

impl AttachLease {
    pub fn grant(&self) -> &AttachGrant {
        &self.grant
    }

    pub fn commit(self) -> AttachGrant {
        self.grant
    }

    pub(crate) fn into_rollback(self) -> AttachRollback {
        self.rollback
    }
}

#[derive(Debug, Clone)]
pub(crate) enum AttachRollback {
    RemoveStartedSession {
        session_id: String,
        expected_generation: u64,
        expected_resume_token: String,
    },
    RestoreResumedSession {
        session_id: String,
        expected_generation: u64,
        expected_resume_token: String,
        previous_state: crate::sync::session_state::SessionState,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SessionAttachError {
    ProtocolError(String),
    SessionExpired { session_id: String, reason: String },
    ResumeRejected { session_id: String, reason: String },
    UnsupportedCapabilities { session_id: String, reason: String },
}

impl SessionAttachError {
    pub fn to_close_frame(&self) -> CloseFrame {
        match self {
            Self::ProtocolError(reason) => CloseFrame {
                close_code: CloseCode::ProtocolError,
                close_reason: Some(reason.clone()),
            },
            Self::SessionExpired { reason, .. } => CloseFrame {
                close_code: CloseCode::SessionExpired,
                close_reason: Some(reason.clone()),
            },
            Self::ResumeRejected { reason, .. } => CloseFrame {
                close_code: CloseCode::ResumeRejected,
                close_reason: Some(reason.clone()),
            },
            Self::UnsupportedCapabilities { reason, .. } => CloseFrame {
                close_code: CloseCode::UnsupportedCapabilities,
                close_reason: Some(reason.clone()),
            },
        }
    }
}

fn generate_resume_token() -> String {
    let mut bytes = [0_u8; 32];
    rand::rng().fill(&mut bytes);
    encode(bytes)
}

fn resume_ack_error_reason(error: &PeerAckError) -> String {
    match error {
        PeerAckError::AckBeyondAssignedEvents {
            ack_up_to,
            last_assigned_event_id,
        } => format!(
            "resume_ack_up_to {ack_up_to} exceeds retained outbound event {last_assigned_event_id}"
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sync::{
        clipboard_domain::{
            ClipboardObservationSource, ClipboardPayload, ClipboardPayloadKind, TextBundle,
        },
        sync_frame::{HtmlMode, ReplayRequirements, SubscribeResume},
    };

    fn capabilities(
        payload_kinds: impl IntoIterator<Item = ClipboardPayloadKind>,
    ) -> SyncCapabilities {
        SyncCapabilities::new(payload_kinds, HtmlMode::Full, 8 * 1024 * 1024)
    }

    fn text_snapshot(value: &str) -> ClipboardSnapshot {
        ClipboardSnapshot::new(
            ClipboardPayload::Text(TextBundle::from_plain_text(value)),
            ClipboardObservationSource::ClipboardWatcher,
        )
    }

    #[tokio::test]
    async fn start_attach_rejects_duplicate_session_ids() {
        let registry = SessionRegistryHandle::new(Duration::from_secs(120));
        let first = registry
            .start_attach(
                "session-1".to_string(),
                capabilities([ClipboardPayloadKind::TextBundle]),
            )
            .await
            .unwrap();
        let duplicate = registry
            .start_attach(
                "session-1".to_string(),
                capabilities([ClipboardPayloadKind::TextBundle]),
            )
            .await
            .unwrap_err();

        assert!(matches!(duplicate, SessionAttachError::ProtocolError(_)));
        registry
            .close_session(&first.grant().session_id, first.grant().attach_generation)
            .await;
    }

    #[tokio::test]
    async fn detached_session_keeps_fan_out_queue_until_ttl_expires() {
        let registry = SessionRegistryHandle::new(Duration::from_secs(120));
        let started = registry
            .start_attach(
                "session-1".to_string(),
                capabilities([ClipboardPayloadKind::TextBundle]),
            )
            .await
            .unwrap()
            .commit();

        registry
            .detach(&started.session_id, started.attach_generation)
            .await;
        registry
            .clipboard_hub()
            .observe_snapshot(text_snapshot("queued while detached"));
        tokio::task::yield_now().await;

        assert_eq!(started.session.pending_outbound_events_after(0).len(), 1);
    }

    #[tokio::test]
    async fn resume_attach_rotates_token_bumps_generation_and_applies_resume_ack() {
        let registry = SessionRegistryHandle::new(Duration::from_secs(120));
        let started = registry
            .start_attach(
                "session-1".to_string(),
                capabilities([ClipboardPayloadKind::TextBundle]),
            )
            .await
            .unwrap()
            .commit();
        started
            .session
            .enqueue_local_snapshot(text_snapshot("pending-1"))
            .unwrap();
        started
            .session
            .enqueue_local_snapshot(text_snapshot("pending-2"))
            .unwrap();

        let first_token = match &started.accepted {
            SubscribeAccepted::Start(accepted) => accepted.resume_token.clone(),
            accepted => panic!("unexpected accepted payload: {accepted:?}"),
        };

        registry
            .detach(&started.session_id, started.attach_generation)
            .await;

        let resumed = registry
            .resume_attach(
                SubscribeResume {
                    session_id: started.session_id.clone(),
                    resume_token: first_token.clone(),
                    resume_ack_up_to: 1,
                    replay_requirements: ReplayRequirements::default(),
                },
                capabilities([ClipboardPayloadKind::TextBundle]),
            )
            .await
            .unwrap()
            .commit();

        let second_token = match &resumed.accepted {
            SubscribeAccepted::Resume(accepted) => {
                assert_eq!(accepted.resume_ack_up_to, 0);
                accepted.resume_token.clone()
            }
            accepted => panic!("unexpected accepted payload: {accepted:?}"),
        };

        assert_ne!(first_token, second_token);
        assert_eq!(resumed.attach_generation, started.attach_generation + 1);
        assert_eq!(resumed.session.pending_outbound_events_after(0).len(), 1);
    }

    #[tokio::test]
    async fn resume_attach_rejects_expired_sessions() {
        let registry = SessionRegistryHandle::new(Duration::ZERO);
        let started = registry
            .start_attach(
                "session-1".to_string(),
                capabilities([ClipboardPayloadKind::TextBundle]),
            )
            .await
            .unwrap()
            .commit();
        let resume_token = match &started.accepted {
            SubscribeAccepted::Start(accepted) => accepted.resume_token.clone(),
            accepted => panic!("unexpected accepted payload: {accepted:?}"),
        };

        registry
            .detach(&started.session_id, started.attach_generation)
            .await;
        tokio::task::yield_now().await;

        let resumed = registry
            .resume_attach(
                SubscribeResume {
                    session_id: started.session_id.clone(),
                    resume_token,
                    resume_ack_up_to: 0,
                    replay_requirements: ReplayRequirements::default(),
                },
                capabilities([ClipboardPayloadKind::TextBundle]),
            )
            .await
            .unwrap_err();

        assert!(matches!(resumed, SessionAttachError::SessionExpired { .. }));
    }
}
