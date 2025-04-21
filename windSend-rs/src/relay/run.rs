async fn run_relay_listener(mut notify_channel: tokio::sync::watch::Receiver<()>) {
    use crate::config;
    use crate::relay::relay_main;
    use tokio::select;
    use tracing::{debug, info};

    info!(
        "run relay server, address: {}",
        config::read_config().relay_server_address,
    );

    let mut wait_duration = std::time::Duration::from_secs(3);
    let mut try_count = 0;

    const MAX_TRY_COUNT: u32 = 30;

    loop {
        select! {
            _ = tokio::time::sleep(wait_duration) => (),
            _ = notify_channel.changed() => (),
        }

        {
            let config = config::read_config();
            if config.relay_server_address.is_empty() || !config.enable_relay {
                debug!("relay server not configured, skip relay");
                continue;
            }
        }

        try_count += 1;
        let connected = relay_main().await;
        if connected {
            if try_count >= MAX_TRY_COUNT {
                wait_duration = std::time::Duration::from_secs(3);
            }
            try_count = 0;
        }

        if try_count == MAX_TRY_COUNT {
            wait_duration = std::time::Duration::from_secs(60);
        }
    }
}

use std::sync::OnceLock;
static RUN_RELAY_LISTENER_ONCE: std::sync::Once = std::sync::Once::new();
static TRY_TO_CONNECT_RELAY_SERVER: OnceLock<tokio::sync::watch::Sender<()>> = OnceLock::new();

pub fn tick_relay() {
    RUN_RELAY_LISTENER_ONCE.call_once(move || {
        let (tx, rx) = tokio::sync::watch::channel(());
        crate::RUNTIME.spawn(run_relay_listener(rx));
        TRY_TO_CONNECT_RELAY_SERVER.set(tx).unwrap();
    });

    let tx = TRY_TO_CONNECT_RELAY_SERVER.get().unwrap();
    tx.send(()).ok();
}
