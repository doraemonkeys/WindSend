use std::sync::LazyLock;
use std::{collections::HashSet, sync::Mutex};

#[cfg(not(feature = "disable-systray-support"))]
use std::sync::OnceLock;
#[cfg(not(feature = "disable-systray-support"))]
pub static TX_RESET_FILES: OnceLock<crossbeam_channel::Sender<()>> = OnceLock::new();
#[cfg(not(feature = "disable-systray-support"))]
pub static TX_CLOSE_QUICK_PAIR: OnceLock<crossbeam_channel::Sender<()>> = OnceLock::new();
#[cfg(not(feature = "disable-systray-support"))]
pub static TX_UPDATE_RELAY_SERVER_CONNECTED: OnceLock<crossbeam_channel::Sender<()>> =
    OnceLock::new();

// pub static TX_CLOSE_ALLOW_TO_BE_SEARCHED: OnceLock<crossbeam_channel::Sender<()>> = OnceLock::new();

pub static SELECTED_FILES: LazyLock<Mutex<HashSet<String>>> =
    LazyLock::new(|| Mutex::new(HashSet::new()));

pub static RELAY_SERVER_CONNECTED: Mutex<bool> = Mutex::new(false);
