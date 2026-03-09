use std::{
    collections::{HashMap, VecDeque},
    sync::{Arc, LazyLock, Mutex},
    time::{Duration, Instant},
};

use tokio::sync::mpsc;
use tracing::trace;

use crate::sync::{
    clipboard_domain::{
        ClipboardFingerprint, ClipboardObservationSource, ClipboardSnapshot,
        ClipboardSuppressionKeys,
    },
    clipboard_watcher::{ClipboardWatcherHandle, start_clipboard_watcher},
};

const REMOTE_APPLY_SUPPRESSION_TTL: Duration = Duration::from_millis(500);

pub static GLOBAL_CLIPBOARD_EVENT_HUB: LazyLock<ClipboardEventHubHandle> =
    LazyLock::new(ClipboardEventHubHandle::new);

#[derive(Clone)]
pub struct ClipboardEventHubHandle {
    inner: Arc<Mutex<ClipboardEventHub>>,
}

impl ClipboardEventHubHandle {
    pub fn new() -> Self {
        Self {
            inner: Arc::new(Mutex::new(ClipboardEventHub::default())),
        }
    }

    pub fn attach_session(&self, session_id: String) -> mpsc::UnboundedReceiver<ClipboardSnapshot> {
        let (sender, receiver) = mpsc::unbounded_channel();
        let should_start_watcher = {
            let mut hub = self.inner.lock().unwrap();
            let was_empty = hub.session_sinks.is_empty();
            hub.session_sinks.insert(session_id, sender);
            was_empty
        };

        if should_start_watcher {
            self.start_watcher();
        }

        receiver
    }

    pub fn detach_session(&self, session_id: &str) {
        let watcher_to_stop = {
            let mut hub = self.inner.lock().unwrap();
            hub.session_sinks.remove(session_id);
            if hub.session_sinks.is_empty() {
                hub.watcher.take()
            } else {
                None
            }
        };

        if let Some(watcher) = watcher_to_stop {
            watcher.stop();
        }
    }

    pub fn record_remote_apply(&self, suppression_keys: ClipboardSuppressionKeys) {
        let mut hub = self.inner.lock().unwrap();
        let now = Instant::now();
        hub.cleanup(now);
        hub.remote_apply_suppressions.push_back(SuppressionEntry {
            suppression_keys,
            expires_at: now + REMOTE_APPLY_SUPPRESSION_TTL,
        });
    }

    pub fn prime_from_current_clipboard(&self) {
        let snapshot = crate::config::CLIPBOARD
            .read_supported_snapshot(ClipboardObservationSource::OnDemandRead);

        if let Ok(snapshot) = snapshot {
            self.observe_internal(snapshot, false);
        }
    }

    pub fn observe_snapshot(&self, snapshot: ClipboardSnapshot) {
        self.observe_internal(snapshot, true);
    }

    fn start_watcher(&self) {
        self.prime_from_current_clipboard();
        let watcher = start_clipboard_watcher(self.clone());

        let watcher_to_stop = {
            let mut hub = self.inner.lock().unwrap();
            if hub.watcher.is_none() && !hub.session_sinks.is_empty() {
                hub.watcher = Some(watcher);
                None
            } else {
                Some(watcher)
            }
        };

        if let Some(watcher) = watcher_to_stop {
            watcher.stop();
        }
    }

    fn observe_internal(&self, snapshot: ClipboardSnapshot, should_emit: bool) {
        let fingerprint = snapshot.fingerprint();
        let suppression_keys = fingerprint.suppression_keys();
        let now = Instant::now();

        let (senders, dead_sessions, suppressed_remote, unchanged_state) = {
            let mut hub = self.inner.lock().unwrap();
            hub.cleanup(now);

            let suppressed_remote = hub
                .remote_apply_suppressions
                .iter()
                .any(|entry| entry.suppression_keys.matches(&suppression_keys));
            let unchanged_state = hub
                .last_observed
                .as_ref()
                .is_some_and(|observed| observed.fingerprint.semantically_matches(&fingerprint));

            hub.last_observed = Some(ObservedClipboardState {
                fingerprint: fingerprint.clone(),
                observed_at: now,
            });

            if !should_emit || suppressed_remote || unchanged_state {
                (Vec::new(), Vec::new(), suppressed_remote, unchanged_state)
            } else {
                let senders = hub
                    .session_sinks
                    .iter()
                    .map(|(session_id, sender)| (session_id.clone(), sender.clone()))
                    .collect::<Vec<_>>();
                (senders, Vec::new(), suppressed_remote, unchanged_state)
            }
        };

        if suppressed_remote {
            trace!("clipboard watcher suppressed a remote-originated apply");
            return;
        }

        if unchanged_state || !should_emit {
            return;
        }

        let mut dead_sessions = dead_sessions;
        for (session_id, sender) in senders {
            if sender.send(snapshot.clone()).is_err() {
                dead_sessions.push(session_id);
            }
        }

        if !dead_sessions.is_empty() {
            let mut hub = self.inner.lock().unwrap();
            for session_id in dead_sessions {
                hub.session_sinks.remove(&session_id);
            }
        }
    }
}

#[derive(Default)]
struct ClipboardEventHub {
    session_sinks: HashMap<String, mpsc::UnboundedSender<ClipboardSnapshot>>,
    watcher: Option<ClipboardWatcherHandle>,
    last_observed: Option<ObservedClipboardState>,
    remote_apply_suppressions: VecDeque<SuppressionEntry>,
}

impl ClipboardEventHub {
    fn cleanup(&mut self, now: Instant) {
        self.remote_apply_suppressions
            .retain(|entry| entry.expires_at > now);
        if let Some(last_observed) = &self.last_observed {
            let is_stale = now.duration_since(last_observed.observed_at) > Duration::from_secs(60);
            if is_stale && self.session_sinks.is_empty() {
                self.last_observed = None;
            }
        }
    }
}

#[derive(Debug, Clone)]
struct ObservedClipboardState {
    fingerprint: ClipboardFingerprint,
    observed_at: Instant,
}

#[derive(Debug, Clone)]
struct SuppressionEntry {
    suppression_keys: ClipboardSuppressionKeys,
    expires_at: Instant,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sync::clipboard_domain::{ClipboardPayload, TextBundle};

    fn text_snapshot(value: &str) -> ClipboardSnapshot {
        ClipboardSnapshot::new(
            ClipboardPayload::Text(TextBundle::from_plain_text(value)),
            ClipboardObservationSource::ClipboardWatcher,
        )
    }

    #[tokio::test]
    async fn remote_applies_update_baseline_without_fan_out() {
        let hub = ClipboardEventHubHandle::new();
        let mut receiver = hub.attach_session("session-1".to_string());

        let snapshot = text_snapshot("remote");
        hub.record_remote_apply(snapshot.fingerprint().suppression_keys());
        hub.observe_snapshot(snapshot.clone());

        assert!(receiver.try_recv().is_err());

        hub.observe_snapshot(snapshot.clone());
        assert!(receiver.try_recv().is_err());
    }

    #[tokio::test]
    async fn semantic_duplicates_are_not_fanned_out_twice() {
        let hub = ClipboardEventHubHandle::new();
        let mut receiver = hub.attach_session("session-1".to_string());

        hub.observe_snapshot(text_snapshot("a"));
        hub.observe_snapshot(text_snapshot("a"));

        let first = receiver.recv().await.unwrap();
        assert_eq!(
            first.payload.kind(),
            crate::sync::clipboard_domain::ClipboardPayloadKind::TextBundle
        );
        assert!(receiver.try_recv().is_err());
    }
}
