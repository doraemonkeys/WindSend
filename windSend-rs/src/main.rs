// hide console window on Windows in release
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::sync::OnceLock;
use tracing::{debug, error, info, trace, warn};
mod config;
mod file;
mod language;
mod route;
mod utils;

// #[cfg(not(all(target_os = "linux", target_env = "musl")))]
#[cfg(not(feature = "disable-systray-support"))]
mod icon_bytes;
#[cfg(not(feature = "disable-systray-support"))]
mod systray;
#[cfg(not(feature = "disable-systray-support"))]
mod web;
#[cfg(not(feature = "disable-systray-support"))]
pub static TX_RESET_FILES: OnceLock<crossbeam_channel::Sender<()>> = OnceLock::new();
#[cfg(not(feature = "disable-systray-support"))]
pub static TX_CLOSE_QUICK_PAIR: OnceLock<crossbeam_channel::Sender<()>> = OnceLock::new();
// pub static TX_CLOSE_ALLOW_TO_BE_SEARCHED: OnceLock<crossbeam_channel::Sender<()>> = OnceLock::new();

use std::{collections::HashSet, sync::Mutex};
pub static SELECTED_FILES: OnceLock<Mutex<HashSet<String>>> = OnceLock::new();

#[allow(dead_code)]
static PROGRAM_NAME: &str = "WindSend-S-Rust";
#[allow(dead_code)]
static PROGRAM_URL: &str = "https://github.com/doraemonkeys/WindSend";
#[allow(dead_code)]
static PROGRAM_VERSION: &str = env!("CARGO_PKG_VERSION");

pub static RUNTIME: OnceLock<tokio::runtime::Runtime> = OnceLock::new();

fn init() {
    config::init();
    let r = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .unwrap();
    RUNTIME.set(r).unwrap();
    SELECTED_FILES.set(Mutex::new(HashSet::new())).unwrap();
    let default_panic = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |panic_info| {
        default_panic(panic_info);
        panic_hook(panic_info);
    }));
}

fn panic_hook(info: &std::panic::PanicInfo) {
    error!("panic: {}", info);
    let backtrace = backtrace::Backtrace::new();
    let panic_message = format!("Panic: {}\n{:?}\n\nBacktrace:\n{:?}", info, info, backtrace);
    if let Ok(mut f) = std::fs::OpenOptions::new()
        .append(true)
        .create(true)
        .open(std::path::Path::new(config::DEFAULT_LOG_DIR).join("panic.log"))
    {
        use std::io::Write;
        let _ = writeln!(f, "{}", panic_message);
    }
    std::process::abort();
}

fn main() {
    init();

    #[cfg(not(feature = "disable-systray-support"))]
    {
        let show_systray_icon = config::GLOBAL_CONFIG.read().unwrap().show_systray_icon;
        if !show_systray_icon {
            return RUNTIME.get().unwrap().block_on(async_main());
        }

        let main_handle = std::thread::spawn(|| {
            RUNTIME.get().unwrap().block_on(async_main());
        });

        let (tx1, rx1) = crossbeam_channel::bounded(1);
        let (tx2, rx2) = crossbeam_channel::bounded(1);
        TX_RESET_FILES.set(tx1).unwrap();
        TX_CLOSE_QUICK_PAIR.set(tx2).unwrap();
        let rm = systray::MenuReceiver {
            rx_reset_files_item: rx1,
            rx_close_quick_pair: rx2,
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
        RUNTIME.get().unwrap().block_on(async_main());
    }
}

async fn async_main() {
    trace!("async_main");
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
