// hide console window on Windows in release
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use crossbeam_channel;

use std::{sync::OnceLock, thread};
use tracing::{debug, error, info, trace, warn};
mod config;
mod file;
mod icon_bytes;
mod language;
mod route;
mod utils;

mod systray;
#[cfg(not(all(target_os = "linux", target_env = "musl")))]
mod web;

pub static RUNTIME: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
pub static TX_RESET_FILES_ITEM: OnceLock<crossbeam_channel::Sender<()>> = OnceLock::new();
pub static TX_CLOSE_ALLOW_TO_BE_SEARCHED: OnceLock<crossbeam_channel::Sender<()>> = OnceLock::new();

static PROGRAM_NAME: &str = "WindSend-S-Rust";
static PROGRAM_URL: &str = "https://github.com/doraemonkeys/WindSend";
static PROGRAM_VERSION: &str = env!("CARGO_PKG_VERSION");

fn init() {
    config::init();
    let r = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .unwrap();
    RUNTIME.set(r).unwrap();
}

fn main() {
    init();

    let main_handle = thread::spawn(|| {
        RUNTIME.get().unwrap().block_on(async_main());
    });

    let (tx1, rx1) = crossbeam_channel::bounded(1);
    let (tx2, rx2) = crossbeam_channel::bounded(1);
    TX_RESET_FILES_ITEM.set(tx1).unwrap();
    TX_CLOSE_ALLOW_TO_BE_SEARCHED.set(tx2).unwrap();
    let rm = systray::MenuReceiver {
        rx_reset_files_item: rx1,
        rx_close_allow_to_be_searched: rx2,
    };
    #[cfg(not(all(target_os = "linux", target_env = "musl")))]
    let show_systray_icon = config::GLOBAL_CONFIG.lock().unwrap().show_systray_icon;
    #[cfg(not(all(target_os = "linux", target_env = "musl")))]
    let return_code = match show_systray_icon {
        true => systray::show_systray(rm),
        false => systray::ReturnCode::HideIcon,
    };
    #[cfg(all(target_os = "linux", target_env = "musl"))]
    let return_code = systray::ReturnCode::HideIcon;

    info!("systray return code: {:?}", return_code);

    match return_code {
        systray::ReturnCode::QUIT => return,
        systray::ReturnCode::HideIcon => main_handle.join().unwrap(),
    }
}

async fn async_main() {
    trace!("async_main");
    let server_port = config::GLOBAL_CONFIG
        .lock()
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
    }
    socket
        .bind((std::net::Ipv6Addr::UNSPECIFIED, server_port).into())
        .expect("bind error");
    let listener = socket.listen(1024).expect("listen error");
    info!("program listening on {}", listener.local_addr().unwrap());
    let tls_acceptor = config::get_tls_acceptor()
        .expect("get tls acceptor error, please check your tls config file");
    loop {
        let result = listener.accept().await;
        if let Err(e) = result {
            error!("accept error: {}", e);
            continue;
        }
        let (stream, addr) = result.unwrap();
        info!("accept a new connection from {}", addr);
        // tls_acceptor.accept_with(stream, f)
        let tls_stream = match tls_acceptor.accept(stream).await {
            Ok(tls_stream) => tls_stream,
            Err(err) => {
                error!("tls accept error: {}", err);
                // panic!("tls accept error: {}", err);
                continue;
            }
        };
        debug!("tls accept success");
        RUNTIME
            .get()
            .unwrap()
            .spawn(route::main_process(tls_stream));
    }
}
