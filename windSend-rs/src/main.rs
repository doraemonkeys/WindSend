// hide console window on Windows in release
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use tracing::{debug, error, info, trace, warn};
mod config;
mod file;
mod language;
mod relay;
mod route;
mod status;
mod utils;
use std::sync::LazyLock;

// #[cfg(not(all(target_os = "linux", target_env = "musl")))]
#[cfg(not(feature = "disable-systray-support"))]
mod icon_bytes;
#[cfg(not(feature = "disable-systray-support"))]
mod systray;
#[cfg(not(feature = "disable-systray-support"))]
mod web;

#[allow(dead_code)]
static PROGRAM_NAME: &str = "WindSend-S-Rust";
#[allow(dead_code)]
static PROGRAM_URL: &str = "https://github.com/doraemonkeys/WindSend";
#[allow(dead_code)]
static PROGRAM_VERSION: &str = env!("CARGO_PKG_VERSION");
static MAC_APP_LABEL: &str = "com.doraemon.windsend.rs";

pub static RUNTIME: LazyLock<tokio::runtime::Runtime> = LazyLock::new(|| {
    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .unwrap()
});

fn init() {
    config::init();
    let default_panic = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |panic_info| {
        default_panic(panic_info);
        panic_hook(panic_info);
    }));
}

fn panic_hook(info: &std::panic::PanicHookInfo) {
    error!("panic: {}", info);
    let backtrace = backtrace::Backtrace::new();
    let panic_message = format!("Panic: {info}\n{info:?}");
    let panic_log_message = format!("{panic_message}\n\nBacktrace:\n{backtrace:?}");
    if let Ok(mut f) = std::fs::OpenOptions::new()
        .append(true)
        .create(true)
        .open(std::path::Path::new(&*config::DEFAULT_LOG_DIR).join("panic.log"))
    {
        use std::io::Write;
        let _ = writeln!(f, "{panic_log_message}");
    }
    #[cfg(not(feature = "disable-systray-support"))]
    {
        use rfd::{MessageDialog, MessageLevel::Error};
        _ = MessageDialog::new()
            .set_title("WindSend-S-Rust")
        .set_description(format!(
            "WindSend-S-Rust has crashed. Please check the log file for more information.\n\n{panic_message}",
        ))
            .set_level(Error)
            .show();
    }
    std::process::abort();
}

fn main() {
    init();
    utils::log_path_info();

    //TODO: Remove this code after a long time
    #[cfg(target_os = "linux")]
    {
        let desktop_file_path =
            dirs::config_dir().map(|dir| dir.join("autostart").join("windsend.desktop"));
        if let Some(desktop_file_path) = desktop_file_path {
            std::fs::remove_file(desktop_file_path).ok();
        }
    }

    #[cfg(not(feature = "disable-systray-support"))]
    {
        let show_systray_icon = config::GLOBAL_CONFIG.read().unwrap().show_systray_icon;
        if !show_systray_icon {
            return RUNTIME.block_on(async_main());
        }

        let main_handle = std::thread::spawn(|| {
            RUNTIME.block_on(async_main());
        });

        let (tx1, rx1) = crossbeam_channel::bounded(1);
        let (tx2, rx2) = crossbeam_channel::bounded(1);
        let (tx3, rx3) = crossbeam_channel::bounded(1);
        status::TX_RESET_FILES.set(tx1).unwrap();
        status::TX_CLOSE_QUICK_PAIR.set(tx2).unwrap();
        status::TX_UPDATE_RELAY_SERVER_CONNECTED.set(tx3).unwrap();
        let rm = systray::MenuReceiver {
            rx_reset_files_item: rx1,
            rx_close_quick_pair: rx2,
            rx_update_relay_server_connected: rx3,
        };

        let return_code = systray::show_systray(rm);
        info!("systray return code: {:?}", return_code);
        match return_code {
            systray::ReturnCode::Quit => (),
            systray::ReturnCode::HideIcon => main_handle.join().unwrap(),
        }
    }
    #[cfg(feature = "disable-systray-support")]
    {
        RUNTIME.block_on(async_main());
    }
}

async fn async_main() {
    loop {
        _async_main().await;
        tokio::time::sleep(std::time::Duration::from_secs(5)).await;
    }
}

async fn _async_main() {
    trace!("async_main");

    {
        let config = config::read_config();
        if config.enable_relay && !config.relay_server_address.is_empty() {
            relay::run::tick_relay();
        }
    }

    let server_port = config::GLOBAL_CONFIG
        .read()
        .unwrap()
        .server_port
        .parse::<u16>()
        .expect("parse server port error");
    let socket = tokio::net::TcpSocket::new_v6().unwrap();
    {
        let socket_ref = socket2::SockRef::from(&socket);
        if let Err(e) = socket_ref.set_only_v6(false) {
            warn!("set_only_v6 error: {}", e);
        }
        // Enable SO_REUSEADDR
        // if let Err(e) = socket_ref.set_reuse_address(true) {
        //     error!("Failed to set SO_REUSEADDR: {}", e);
        //     return;
        // }
    }
    socket
        .bind((std::net::Ipv6Addr::UNSPECIFIED, server_port).into())
        .expect("bind error");
    let listener = socket.listen(1024).expect("listen error");
    info!("program listening on {}", listener.local_addr().unwrap());
    let tls_acceptor = config::TLS_ACCEPTOR.clone();
    loop {
        let result = listener.accept().await;
        if let Err(e) = result {
            error!("accept error: {}", e);
            #[cfg(target_os = "windows")]
            if e.to_string().contains("WSAStartup") {
                // restart listener
                return;
            }
            continue;
        }
        let (stream, addr) = result.unwrap();
        info!("accept a new connection from {}", addr);
        // tls_acceptor.accept_with(stream, f)
        let tls_stream = match tls_acceptor.accept(stream).await {
            Ok(tls_stream) => tls_stream,
            Err(err) => {
                error!("unknown connection({}), tls accept error: {}", addr, err);
                // panic!("tls accept error: {}", err);
                continue;
            }
        };
        debug!("tls accept success");
        RUNTIME.spawn(route::main_process(tls_stream));
    }
}
