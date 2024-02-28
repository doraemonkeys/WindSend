// hide console window on Windows in release
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::collections::HashSet;
use std::sync::{Mutex, OnceLock};
use std::thread;
use tracing::{debug, error, info, trace, warn};
mod config;
mod file;
mod language;
mod route;
mod utils;

#[cfg(not(all(target_os = "linux", target_env = "musl")))]
mod icon_bytes;
#[cfg(not(all(target_os = "linux", target_env = "musl")))]
mod systray;
#[cfg(not(all(target_os = "linux", target_env = "musl")))]
mod web;

#[cfg(not(all(target_os = "linux", target_env = "musl")))]
pub static TX_RESET_FILES_ITEM: OnceLock<crossbeam_channel::Sender<()>> = OnceLock::new();
#[cfg(not(all(target_os = "linux", target_env = "musl")))]
// pub static TX_CLOSE_ALLOW_TO_BE_SEARCHED: OnceLock<crossbeam_channel::Sender<()>> = OnceLock::new();
pub static TX_CLOSE_QUICK_PAIR: OnceLock<crossbeam_channel::Sender<()>> = OnceLock::new();

#[allow(unused_variables)]
static PROGRAM_NAME: &str = "WindSend-S-Rust";
#[allow(unused_variables)]
static PROGRAM_URL: &str = "https://github.com/doraemonkeys/WindSend";
#[allow(unused_variables)]
static PROGRAM_VERSION: &str = env!("CARGO_PKG_VERSION");
#[cfg(not(feature = "disable_select_file"))]
pub static SELECTED_FILES: OnceLock<Mutex<HashSet<String>>> = OnceLock::new();

pub static RUNTIME: OnceLock<tokio::runtime::Runtime> = OnceLock::new();

fn init() {
    config::init();
    let r = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .unwrap();
    RUNTIME.set(r).unwrap();
    #[cfg(not(feature = "disable_select_file"))]
    SELECTED_FILES.set(Mutex::new(HashSet::new())).unwrap();
}

fn main() {
    init();

    let main_handle = thread::spawn(|| {
        RUNTIME.get().unwrap().block_on(async_main());
    });

    #[cfg(not(all(target_os = "linux", target_env = "musl")))]
    {
        let (tx1, rx1) = crossbeam_channel::bounded(1);
        let (tx2, rx2) = crossbeam_channel::bounded(1);
        TX_RESET_FILES_ITEM.set(tx1).unwrap();
        TX_CLOSE_QUICK_PAIR.set(tx2).unwrap();
        let rm = systray::MenuReceiver {
            rx_reset_files_item: rx1,
            rx_close_quick_pair: rx2,
        };
        let show_systray_icon = config::GLOBAL_CONFIG.lock().unwrap().show_systray_icon;
        let return_code = match show_systray_icon {
            true => systray::show_systray(rm),
            false => systray::ReturnCode::HideIcon,
        };
        info!("systray return code: {:?}", return_code);
        match return_code {
            systray::ReturnCode::QUIT => return,
            systray::ReturnCode::HideIcon => main_handle.join().unwrap(),
        }
    }
    #[cfg(all(target_os = "linux", target_env = "musl"))]
    {
        main_handle.join().unwrap();
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
