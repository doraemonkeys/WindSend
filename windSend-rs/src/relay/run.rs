/// Maintains exactly one idle Rust↔Go control connection at all times.
///
/// # Connection lifecycle ("use-once, replenish immediately")
///
/// Each Rust↔Go TCP connection serves a single relay bridge session, then is
/// closed. When a Relay command arrives, the connection is handed off to a
/// spawned task and this loop immediately reconnects to establish a fresh idle
/// connection for the next request.
///
/// This is the **bridge-level** (session-level) lifecycle. *Within* a single
/// bridge session, the Flutter↔Rust TLS connection is long-lived: `main_process`
/// handles multiple requests (e.g. file chunks) on the same TLS stream, and
/// Flutter's `ConnectionManager.get/put` reuses it across workers — identical
/// to the direct-connect path.
async fn run_relay_listener(
    mut notify_channel: tokio::sync::watch::Receiver<()>,
    mut shutdown_rx: tokio::sync::watch::Receiver<bool>,
) {
    use crate::config;
    use crate::relay::{RelayExitReason, relay_main};
    use tokio::select;
    use tokio::task::JoinSet;
    use tracing::{debug, error, info};

    info!(
        "run relay server, address: {}",
        config::read_config().relay_server_address,
    );

    let mut wait_duration = std::time::Duration::from_secs(3);
    let mut try_count: u32 = 0;
    let mut join_set: JoinSet<()> = JoinSet::new();

    const MAX_TRY_COUNT: u32 = 30;

    loop {
        // Reap completed relay tasks before each iteration.
        while let Some(result) = join_set.try_join_next() {
            if let Err(e) = result {
                error!("relay task panicked: {e}");
            }
        }

        // Check for shutdown before blocking on sleep/notify. Using
        // `has_changed` avoids consuming the value so subsequent checks
        // still see it.
        if *shutdown_rx.borrow_and_update() {
            break;
        }

        select! {
            _ = tokio::time::sleep(wait_duration) => (),
            _ = notify_channel.changed() => (),
            // Wake immediately when the shutdown signal arrives so we
            // stop spawning new tasks without waiting for the full
            // sleep/backoff duration to elapse.
            _ = shutdown_rx.changed() => {
                break;
            }
        }

        {
            let config = config::read_config();
            if config.relay_server_address.is_empty() || !config.enable_relay {
                debug!("relay server not configured, skip relay");
                // If relay gets disabled right after a successful spawned relay,
                // wait_duration may be ZERO. Reset it to avoid a tight loop.
                wait_duration = std::time::Duration::from_secs(3);
                try_count = 0;
                continue;
            }
        }

        try_count += 1;

        match relay_main().await {
            Some(RelayExitReason::Spawned(fut)) => {
                join_set.spawn(fut);
                // Reset backoff: the connection was healthy enough to
                // receive a relay request, so reconnect immediately.
                try_count = 0;
                // Skip the sleep at loop top -- reconnect right away to
                // maintain an idle connection for the next relay request.
                wait_duration = std::time::Duration::ZERO;
                continue;
            }
            Some(RelayExitReason::Disconnected) => {
                // Connection was established but dropped; short wait.
                // relay_main already set status to false for this path.
                try_count = 0;
                wait_duration = std::time::Duration::from_secs(3);
            }
            Some(RelayExitReason::Failed) | None => {
                // Connection setup or protocol failure; apply backoff.
                // relay_main sets status=false for Failed, but returns None
                // without touching status on connection-setup failures. Reset
                // here to avoid a stale `true` left by a prior Spawned.
                crate::relay::update_relay_server_status(false);
                if try_count >= MAX_TRY_COUNT {
                    wait_duration = std::time::Duration::from_secs(60);
                } else {
                    // A previous Spawned path sets wait_duration to ZERO for
                    // immediate reconnect. On failure, restore a non-zero wait
                    // to avoid a hot reconnect loop.
                    wait_duration = std::time::Duration::from_secs(3);
                }
            }
        }
    }

    // Graceful shutdown: let all in-flight relay transfers complete
    // naturally instead of aborting them. Do NOT use join_set.shutdown()
    // as it aborts tasks -- we must drain them one by one.
    let remaining = join_set.len();
    if remaining > 0 {
        info!(
            "relay listener shutting down, waiting for {remaining} in-flight relay task(s) to finish"
        );
        if tokio::time::timeout(std::time::Duration::from_secs(60), async {
            while let Some(result) = join_set.join_next().await {
                if let Err(e) = result {
                    error!("relay task panicked during shutdown drain: {e}");
                }
            }
        })
        .await
        .is_err()
        {
            error!(
                "shutdown drain timed out after 60s, aborting {} remaining task(s)",
                join_set.len()
            );
            join_set.shutdown().await;
        }
    }
    // Ensure UI reflects the true state regardless of how we exited the loop
    // (shutdown signal, config disable, or repeated connection failures after Spawned).
    crate::relay::update_relay_server_status(false);
    info!("relay listener shut down gracefully, all tasks drained");
}

use std::sync::Mutex;

struct RelayState {
    notify_tx: tokio::sync::watch::Sender<()>,
    shutdown_tx: tokio::sync::watch::Sender<bool>,
    /// Set to `true` while the listener is draining after a shutdown signal.
    /// Prevents `tick_relay` from starting a duplicate listener before the
    /// old one has fully exited and cleared the state.
    shutting_down: bool,
}

static RELAY_STATE: std::sync::LazyLock<Mutex<Option<RelayState>>> =
    std::sync::LazyLock::new(|| Mutex::new(None));

pub fn tick_relay() -> bool {
    let mut state = RELAY_STATE.lock().unwrap();
    if let Some(ref s) = *state {
        if s.shutting_down {
            // Listener is draining; don't notify or start a new one.
            return false;
        }
        // Already running — just notify.
        s.notify_tx.send(()).ok();
        return false;
    }
    // First run or restart after shutdown.
    let (tx, rx) = tokio::sync::watch::channel(());
    let (shutdown_tx, shutdown_rx) = tokio::sync::watch::channel(false);
    crate::RUNTIME.spawn(async {
        run_relay_listener(rx, shutdown_rx).await;
        // Listener has fully stopped — clear state so a future tick_relay
        // can start a fresh one.
        *RELAY_STATE.lock().unwrap() = None;
    });
    *state = Some(RelayState {
        notify_tx: tx,
        shutdown_tx,
        shutting_down: false,
    });
    true
}

/// Signal the relay listener to stop accepting new relay requests and
/// drain all in-flight relay tasks to completion. This lets active
/// transfers finish naturally without being aborted.
///
/// Returns `true` if the shutdown signal was sent successfully, `false`
/// if the relay listener was never started or the channel is closed.
#[allow(dead_code)]
pub fn shutdown_relay() -> bool {
    let mut state = RELAY_STATE.lock().unwrap();
    match state.as_mut() {
        Some(s) if !s.shutting_down => {
            s.shutting_down = true;
            s.shutdown_tx.send(true).is_ok()
        }
        _ => false,
    }
}
