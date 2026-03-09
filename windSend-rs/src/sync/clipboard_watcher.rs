use std::{
    sync::mpsc::{self, RecvTimeoutError, Sender},
    thread,
    time::Duration,
};

use clipboard_rs::{ClipboardHandler, ClipboardWatcher, ClipboardWatcherContext, WatcherShutdown};
use tracing::{trace, warn};

use crate::sync::{
    clipboard_domain::ClipboardObservationSource, clipboard_event_hub::ClipboardEventHubHandle,
};

pub const WATCHER_POLL_INTERVAL: Duration = Duration::from_millis(100);

pub fn start_clipboard_watcher(hub: ClipboardEventHubHandle) -> ClipboardWatcherHandle {
    match start_native_clipboard_watcher(hub.clone()) {
        Ok(handle) => handle,
        Err(error) => {
            warn!(
                ?error,
                "native clipboard watcher unavailable, falling back to polling"
            );
            start_polling_clipboard_watcher(hub)
        }
    }
}

pub(crate) enum ClipboardWatcherHandle {
    Native(NativeClipboardWatcher),
    Polling(PollingClipboardWatcher),
}

impl ClipboardWatcherHandle {
    pub fn stop(mut self) {
        self.stop_in_place();
    }

    fn stop_in_place(&mut self) {
        match self {
            Self::Native(native) => native.stop_in_place(),
            Self::Polling(polling) => polling.stop_in_place(),
        }
    }
}

impl Drop for ClipboardWatcherHandle {
    fn drop(&mut self) {
        self.stop_in_place();
    }
}

pub(crate) struct NativeClipboardWatcher {
    shutdown: Option<WatcherShutdown>,
    thread: Option<std::thread::JoinHandle<()>>,
}

impl NativeClipboardWatcher {
    fn stop_in_place(&mut self) {
        if let Some(shutdown) = self.shutdown.take() {
            shutdown.stop();
        }
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

pub(crate) struct PollingClipboardWatcher {
    stop_tx: Option<Sender<()>>,
    thread: Option<std::thread::JoinHandle<()>>,
}

impl PollingClipboardWatcher {
    fn stop_in_place(&mut self) {
        if let Some(stop_tx) = self.stop_tx.take() {
            let _ = stop_tx.send(());
        }
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

fn start_native_clipboard_watcher(
    hub: ClipboardEventHubHandle,
) -> Result<ClipboardWatcherHandle, Box<dyn std::error::Error + Send + Sync>> {
    let mut watcher: ClipboardWatcherContext<HubClipboardHandler> = ClipboardWatcherContext::new()?;
    let shutdown = watcher
        .add_handler(HubClipboardHandler { hub })
        .get_shutdown_channel();
    let thread = thread::Builder::new()
        .name("windsend-clipboard-watcher".to_string())
        .spawn(move || watcher.start_watch())?;

    Ok(ClipboardWatcherHandle::Native(NativeClipboardWatcher {
        shutdown: Some(shutdown),
        thread: Some(thread),
    }))
}

fn start_polling_clipboard_watcher(hub: ClipboardEventHubHandle) -> ClipboardWatcherHandle {
    let (stop_tx, stop_rx) = mpsc::channel();
    let thread = thread::Builder::new()
        .name("windsend-clipboard-poll".to_string())
        .spawn(move || {
            loop {
                match stop_rx.recv_timeout(WATCHER_POLL_INTERVAL) {
                    Ok(()) | Err(RecvTimeoutError::Disconnected) => break,
                    Err(RecvTimeoutError::Timeout) => {
                        let snapshot = crate::config::CLIPBOARD
                            .read_supported_snapshot(ClipboardObservationSource::ClipboardWatcher);
                        match snapshot {
                            Ok(snapshot) => hub.observe_snapshot(snapshot),
                            Err(error) => {
                                trace!(
                                    ?error,
                                    "clipboard polling skipped unsupported clipboard state"
                                )
                            }
                        }
                    }
                }
            }
        })
        .expect("failed to spawn clipboard polling thread");

    ClipboardWatcherHandle::Polling(PollingClipboardWatcher {
        stop_tx: Some(stop_tx),
        thread: Some(thread),
    })
}

struct HubClipboardHandler {
    hub: ClipboardEventHubHandle,
}

impl ClipboardHandler for HubClipboardHandler {
    fn on_clipboard_change(&mut self) {
        let snapshot = crate::config::CLIPBOARD
            .read_supported_snapshot(ClipboardObservationSource::ClipboardWatcher);

        match snapshot {
            Ok(snapshot) => self.hub.observe_snapshot(snapshot),
            Err(error) => {
                trace!(
                    ?error,
                    "clipboard watcher skipped unsupported clipboard state"
                )
            }
        }
    }
}
