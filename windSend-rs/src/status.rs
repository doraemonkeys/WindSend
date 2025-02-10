use std::sync::OnceLock;
use std::{collections::HashSet, sync::Mutex};

#[cfg(not(feature = "disable-systray-support"))]
pub static TX_RESET_FILES: OnceLock<crossbeam_channel::Sender<()>> = OnceLock::new();
#[cfg(not(feature = "disable-systray-support"))]
pub static TX_CLOSE_QUICK_PAIR: OnceLock<crossbeam_channel::Sender<()>> = OnceLock::new();
// pub static TX_CLOSE_ALLOW_TO_BE_SEARCHED: OnceLock<crossbeam_channel::Sender<()>> = OnceLock::new();

pub static SELECTED_FILES: OnceLock<Mutex<HashSet<String>>> = OnceLock::new();

#[allow(unused)]
#[allow(dead_code)]
pub static RELAY_SERVER_CONNECTED: Mutex<bool> = Mutex::new(false);
#[cfg(not(feature = "disable-systray-support"))]
pub static TX_UPDATE_RELAY_SERVER_CONNECTED: OnceLock<crossbeam_channel::Sender<()>> =
    OnceLock::new();
