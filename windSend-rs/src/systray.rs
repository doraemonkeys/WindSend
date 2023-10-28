use std::collections::HashSet;
use std::sync::Mutex;
use std::sync::OnceLock;
use tao::event_loop::{ControlFlow, EventLoopBuilder};
use tao::platform::run_return::EventLoopExtRunReturn;
use tracing::{debug, error, warn};
use tray_icon::menu::{
    AboutMetadata, CheckMenuItem, IsMenuItem, Menu, MenuEvent, MenuItem, PredefinedMenuItem,
    SubmenuBuilder,
};
use tray_icon::TrayIconBuilder;

use crate::config;
use crate::utils;
use crate::web;

// use global_hotkey::hotkey::Modifiers as hotkey_Modifiers;
// use global_hotkey::{
//     hotkey::{Code, HotKey},
//     GlobalHotKeyEvent, GlobalHotKeyManager, HotKeyState,
// };
// use tray_icon::menu::accelerator::Accelerator;
// use tray_icon::menu::accelerator::Modifiers;

pub static SELECTED_FILES: OnceLock<Mutex<HashSet<String>>> = OnceLock::new();

#[derive(Debug)]
pub enum ReturnCode {
    HideIcon = 1000,
    QUIT = 0,
}

pub fn show_systray(rx_reset_files_item: crossbeam_channel::Receiver<()>) -> ReturnCode {
    SELECTED_FILES.set(Mutex::new(HashSet::new())).unwrap();
    loop_systray(rx_reset_files_item)
}

fn loop_systray(rx_reset_files_item: crossbeam_channel::Receiver<()>) -> ReturnCode {
    let icon = load_icon();

    let tray_menu = Menu::new();

    let add_files_i = MenuItem::new("添加文件 - 0", true, None);
    let clear_files_i = MenuItem::new("清空文件", false, None);
    let sub_hide_once_i = MenuItem::new("仅一次", true, None);
    let sub_hide_forever_i = MenuItem::new("永久隐藏", true, None);
    let auto_start_i = CheckMenuItem::new(
        "开机自启",
        true,
        config::GLOBAL_CONFIG.lock().unwrap().auto_start,
        None,
    );
    // let copy_from_web_shortcut = Accelerator::new(
    //     Some(Modifiers::CONTROL | Modifiers::ALT),
    //     tray_icon::menu::accelerator::Code::KeyY,
    // );
    // let paste_to_web_shortcut = Accelerator::new(
    //     Some(Modifiers::CONTROL | Modifiers::ALT),
    //     tray_icon::menu::accelerator::Code::KeyP,
    // );
    // let hotkey_copy = HotKey::new(
    //     Some(hotkey_Modifiers::CONTROL | hotkey_Modifiers::ALT),
    //     Code::KeyY,
    // );
    // let hotkey_paste = HotKey::new(
    //     Some(hotkey_Modifiers::CONTROL | hotkey_Modifiers::ALT),
    //     Code::KeyP,
    // );
    // let hotkeys_manager = GlobalHotKeyManager::new().unwrap();
    // hotkeys_manager.register(hotkey_copy).unwrap();
    // hotkeys_manager.register(hotkey_paste).unwrap();
    // let global_hotkey_channel = GlobalHotKeyEvent::receiver();

    let copy_from_web_i = MenuItem::new("复制[Web]", true, None);
    let paste_to_web_i = MenuItem::new("粘贴[Web]", true, None);

    let open_url_i = MenuItem::new("打开官网", true, None);
    let save_path_i = MenuItem::new("文件保存路径", true, None);
    let sub_menu_hide = SubmenuBuilder::new()
        .text("隐藏图标")
        .item(&sub_hide_once_i)
        .item(&sub_hide_forever_i)
        .enabled(true)
        .build()
        .unwrap();
    let about_i = PredefinedMenuItem::about(
        Some("关于"),
        Some(AboutMetadata {
            name: Some(crate::PROGRAM_NAME.to_string()),
            version: Some(crate::PROGRAM_VERSION.to_string()),
            ..Default::default()
        }),
    );
    let items: &[&dyn IsMenuItem] = &[
        &add_files_i,
        &clear_files_i,
        &copy_from_web_i,
        &paste_to_web_i,
        &sub_menu_hide,
        &PredefinedMenuItem::separator(),
        #[cfg(not(target_os = "linux"))]
        &auto_start_i,
        &save_path_i,
        &open_url_i,
        &PredefinedMenuItem::separator(),
        &about_i,
        &PredefinedMenuItem::quit(Some("退出")),
    ];
    tray_menu.append_items(items).unwrap();

    let mut tray_icon = Some(
        TrayIconBuilder::new()
            .with_menu(Box::new(tray_menu))
            .with_tooltip(String::from(crate::PROGRAM_NAME) + " " + crate::PROGRAM_VERSION)
            .with_icon(icon)
            .build()
            .unwrap(),
    );
    let menu_channel = MenuEvent::receiver();
    // 点击托盘图标事件
    // let tray_channel = TrayIconEvent::receiver();

    let mut event_loop = EventLoopBuilder::new().build();
    let return_code = event_loop.run_return(move |_event, _, control_flow| {
        // println!("event_loop");
        *control_flow = ControlFlow::Wait;
        if let Ok(_) = rx_reset_files_item.try_recv() {
            handle_menu_event_clear_files(&add_files_i, &clear_files_i);
        }
        // 不能一直阻塞在这里，否则右键点击托盘图标会没有反应
        if let Ok(event) = menu_channel.try_recv() {
            match event.id {
                id if id == sub_hide_once_i.id() || id == sub_hide_forever_i.id() => {
                    *control_flow = ControlFlow::ExitWithCode(ReturnCode::HideIcon as i32);
                }
                id if id == add_files_i.id() => {
                    let r = crate::RUNTIME.get().unwrap();
                    r.block_on(handle_menu_event_add_files(&add_files_i, &clear_files_i));
                }
                id if id == clear_files_i.id() => {
                    handle_menu_event_clear_files(&add_files_i, &clear_files_i);
                }
                id if id == paste_to_web_i.id() => {
                    let r = crate::RUNTIME.get().unwrap();
                    r.spawn(handle_menu_event_paste_to_web());
                }
                id if id == copy_from_web_i.id() => {
                    let r = crate::RUNTIME.get().unwrap();
                    r.spawn(handle_menu_event_copy_from_web());
                }
                id if id == auto_start_i.id() => {
                    let mut config = config::GLOBAL_CONFIG.lock().unwrap();
                    config.auto_start = !config.auto_start;
                    if let Err(err) = config.save_and_set() {
                        error!("save config error: {}", err);
                    }
                }
                id if id == save_path_i.id() => {
                    let r = crate::RUNTIME.get().unwrap();
                    r.block_on(handle_menu_event_save_path());
                }
                id if id == open_url_i.id() => {
                    if let Err(err) = crate::utils::open_url(crate::PROGRAM_URL) {
                        error!("open url error: {}", err);
                    }
                }
                other_id => {
                    // println!("recv unknown menu event, id: {:?}", other_id);
                    error!("recv unknown menu event, id: {:?}", other_id);
                }
            }
        }
    });
    tray_icon.take(); //keep icon alive until the end of the program
    const HIDE_ICON_CODE: i32 = ReturnCode::HideIcon as i32;
    match return_code {
        0 => ReturnCode::QUIT,
        HIDE_ICON_CODE => ReturnCode::HideIcon,
        code => std::process::exit(code),
    }
}

async fn handle_menu_event_add_files(add_item: &MenuItem, clear_item: &MenuItem) {
    let pick_task = rfd::AsyncFileDialog::new().pick_files();
    let files = match pick_task.await {
        Some(files) => files,
        None => {
            warn!("pick_files failed");
            return;
        }
    };
    let mut selected_files = SELECTED_FILES.get().unwrap().lock().unwrap();
    for file in files {
        debug!("selected file: {:?}", file);
        selected_files.insert(file.path().to_str().unwrap().to_string());
    }
    clear_item.set_enabled(true);
    add_item.set_text(format!("添加文件 - {}", selected_files.len()));
}

async fn handle_menu_event_save_path() {
    let pick_task = rfd::AsyncFileDialog::new().pick_folder();
    let path = match pick_task.await {
        Some(path) => path,
        None => {
            warn!("pick folder error");
            return;
        }
    };
    let mut config = config::GLOBAL_CONFIG.lock().unwrap();
    config.save_path = path.path().to_str().unwrap().to_string();
    debug!("change save path to: {}", config.save_path);
    if let Err(err) = config.save_and_set() {
        error!("save config error: {}", err);
    }
}

async fn handle_menu_event_paste_to_web() {
    let clipboard_text = config::CLIPBOARD.lock().unwrap().get_text();
    if clipboard_text.is_err() {
        error!(
            "get clipboard text error: {}",
            clipboard_text.err().unwrap()
        );
        return;
    }
    debug!("clipboard_text: {:?}", clipboard_text);
    let clipboard_text = clipboard_text.unwrap();
    let result = web::post_content_to_web(clipboard_text.as_bytes()).await;
    if result.is_err() {
        error!("post content to web error: {}", result.err().unwrap());
        return;
    }
    utils::inform("粘贴成功");
}

async fn handle_menu_event_copy_from_web() {
    let result = web::get_content_from_web().await;
    if result.is_err() {
        error!("get content from web error: {}", result.err().unwrap());
        return;
    }
    let content = result.unwrap();
    let content = String::from_utf8(content);
    if content.is_err() {
        error!("content is not utf8");
        return;
    }
    let content = content.unwrap();
    debug!("content: {}", content);
    let result = config::CLIPBOARD.lock().unwrap().set_text(&content);
    if result.is_err() {
        error!("set clipboard text error: {}", result.err().unwrap());
        return;
    }
    utils::inform(&content);
}

fn handle_menu_event_clear_files(add_item: &MenuItem, clear_item: &MenuItem) {
    {
        let mut selected_files = SELECTED_FILES.get().unwrap().lock().unwrap();
        selected_files.clear();
        selected_files.shrink_to_fit();
    }
    clear_item.set_enabled(false);
    add_item.set_text(format!("添加文件 - {}", 0));
}

fn load_icon() -> tray_icon::Icon {
    let (icon_rgba, icon_width, icon_height) = {
        let image = image::load_from_memory(crate::icon_bytes::ICON_DATA)
            .expect("Failed to open icon path")
            .into_rgba8();
        let (width, height) = image.dimensions();
        let rgba = image.into_raw();
        (rgba, width, height)
    };
    tray_icon::Icon::from_rgba(icon_rgba, icon_width, icon_height).expect("Failed to open icon")
}
