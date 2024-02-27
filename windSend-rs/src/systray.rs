use std::collections::HashSet;
use std::sync::Mutex;
use std::sync::OnceLock;
use tao::event_loop::{ControlFlow, EventLoopBuilder};
use tao::platform::run_return::EventLoopExtRunReturn;
use tracing::{debug, error, info, warn};
use tray_icon::menu::{
    AboutMetadata, CheckMenuItem, IsMenuItem, Menu, MenuEvent, MenuItem, PredefinedMenuItem,
    Submenu, SubmenuBuilder,
};
use tray_icon::TrayIconBuilder;

use crate::config;
use crate::language::{Language, LanguageKey, LANGUAGE_MANAGER};
use crate::utils;
use crate::web;
use crate::PROGRAM_NAME;

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

pub struct MenuReceiver {
    pub rx_reset_files_item: crossbeam_channel::Receiver<()>,
    pub rx_close_allow_to_be_searched: crossbeam_channel::Receiver<()>,
}

pub fn show_systray(mr: MenuReceiver) -> ReturnCode {
    SELECTED_FILES.set(Mutex::new(HashSet::new())).unwrap();
    loop_systray(mr)
}

fn loop_systray<'a>(mr: MenuReceiver) -> ReturnCode {
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

    // before Menu::new()
    let mut event_loop = EventLoopBuilder::new().build();

    let icon = load_icon();
    let tray_menu = Menu::new();

    let add_files_i = MenuItem::new(
        LANGUAGE_MANAGER
            .read()
            .unwrap()
            .translate(LanguageKey::AddFiles)
            .to_owned()
            + "- 0",
        true,
        None,
    );
    let clear_files_i = MenuItem::new(
        LANGUAGE_MANAGER
            .read()
            .unwrap()
            .translate(LanguageKey::ClearFiles),
        false,
        None,
    );
    let sub_hide_once_i = MenuItem::new(
        LANGUAGE_MANAGER
            .read()
            .unwrap()
            .translate(LanguageKey::OnlyOnce),
        true,
        None,
    );
    let sub_hide_forever_i = MenuItem::new(
        LANGUAGE_MANAGER
            .read()
            .unwrap()
            .translate(LanguageKey::HideForever),
        true,
        None,
    );
    let lang_zh_i = CheckMenuItem::new(
        "简体中文",
        true,
        LANGUAGE_MANAGER.read().unwrap().get_language() == Language::ZH,
        None,
    );
    let lang_en_i = CheckMenuItem::new(
        "English",
        true,
        LANGUAGE_MANAGER.read().unwrap().get_language() == Language::EN,
        None,
    );
    let auto_start = config::GLOBAL_CONFIG.lock().unwrap().auto_start;
    let auto_start_i = CheckMenuItem::new(
        LANGUAGE_MANAGER
            .read()
            .unwrap()
            .translate(LanguageKey::AutoStart),
        true,
        auto_start,
        None,
    );
    let allow_to_be_search_i = CheckMenuItem::new(
        LANGUAGE_MANAGER
            .read()
            .unwrap()
            .translate(LanguageKey::QuickPair),
        true,
        *config::ALLOW_TO_BE_SEARCHED.lock().unwrap(),
        None,
    );
    let copy_from_web_i = MenuItem::new(
        LANGUAGE_MANAGER
            .read()
            .unwrap()
            .translate(LanguageKey::Copy)
            .to_owned()
            + "[Web]",
        true,
        None,
    );
    let paste_to_web_i = MenuItem::new(
        LANGUAGE_MANAGER
            .read()
            .unwrap()
            .translate(LanguageKey::Paste)
            .to_owned()
            + "[Web]",
        true,
        None,
    );
    let save_path_i = MenuItem::new(
        LANGUAGE_MANAGER
            .read()
            .unwrap()
            .translate(LanguageKey::SavePath),
        true,
        None,
    );
    let open_url_i = MenuItem::new(
        LANGUAGE_MANAGER
            .read()
            .unwrap()
            .translate(LanguageKey::OpenOfficialWebsite),
        true,
        None,
    );
    let sub_menu_hide = SubmenuBuilder::new()
        .text(
            LANGUAGE_MANAGER
                .read()
                .unwrap()
                .translate(LanguageKey::HideIcon),
        )
        .item(&sub_hide_once_i)
        .item(&sub_hide_forever_i)
        .enabled(true)
        .build()
        .unwrap();
    let sub_menu_lang = SubmenuBuilder::new()
        .text("Language")
        .item(&lang_zh_i)
        .item(&lang_en_i)
        .enabled(true)
        .build()
        .unwrap();
    let about_i = PredefinedMenuItem::about(
        Some(
            LANGUAGE_MANAGER
                .read()
                .unwrap()
                .translate(LanguageKey::About),
        ),
        Some(AboutMetadata {
            name: Some(crate::PROGRAM_NAME.to_string()),
            version: Some(crate::PROGRAM_VERSION.to_string()),
            ..Default::default()
        }),
    );
    let quit_i = PredefinedMenuItem::quit(Some(
        LANGUAGE_MANAGER
            .read()
            .unwrap()
            .translate(LanguageKey::Quit),
    ));
    let items: &[&dyn IsMenuItem] = &[
        &add_files_i,
        &clear_files_i,
        &copy_from_web_i,
        &paste_to_web_i,
        &PredefinedMenuItem::separator(),
        &save_path_i,
        &sub_menu_hide,
        &sub_menu_lang,
        #[cfg(not(target_os = "linux"))]
        &auto_start_i,
        &PredefinedMenuItem::separator(),
        &allow_to_be_search_i,
        &open_url_i,
        &about_i,
        &quit_i,
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

    let items2: &[(&dyn SetTitle<String>, &dyn Fn() -> String)] = &[
        (&add_files_i, &|| {
            LANGUAGE_MANAGER
                .read()
                .unwrap()
                .translate(LanguageKey::AddFiles)
                .to_owned()
                + "- 0"
        }),
        (&clear_files_i, &|| {
            LANGUAGE_MANAGER
                .read()
                .unwrap()
                .translate(LanguageKey::ClearFiles)
                .clone()
        }),
        (&sub_menu_hide, &|| {
            LANGUAGE_MANAGER
                .read()
                .unwrap()
                .translate(LanguageKey::HideIcon)
                .clone()
        }),
        (&sub_hide_once_i, &|| {
            LANGUAGE_MANAGER
                .read()
                .unwrap()
                .translate(LanguageKey::OnlyOnce)
                .clone()
        }),
        (&sub_hide_forever_i, &|| {
            LANGUAGE_MANAGER
                .read()
                .unwrap()
                .translate(LanguageKey::HideForever)
                .clone()
        }),
        (&auto_start_i, &|| {
            LANGUAGE_MANAGER
                .read()
                .unwrap()
                .translate(LanguageKey::AutoStart)
                .clone()
        }),
        (&allow_to_be_search_i, &|| {
            LANGUAGE_MANAGER
                .read()
                .unwrap()
                .translate(LanguageKey::QuickPair)
                .clone()
        }),
        (&copy_from_web_i, &|| {
            LANGUAGE_MANAGER
                .read()
                .unwrap()
                .translate(LanguageKey::Copy)
                .to_owned()
                + "[Web]"
        }),
        (&paste_to_web_i, &|| {
            LANGUAGE_MANAGER
                .read()
                .unwrap()
                .translate(LanguageKey::Paste)
                .to_owned()
                + "[Web]"
        }),
        (&save_path_i, &|| {
            LANGUAGE_MANAGER
                .read()
                .unwrap()
                .translate(LanguageKey::SavePath)
                .clone()
        }),
        (&open_url_i, &|| {
            LANGUAGE_MANAGER
                .read()
                .unwrap()
                .translate(LanguageKey::OpenOfficialWebsite)
                .clone()
        }),
        (&about_i, &|| {
            LANGUAGE_MANAGER
                .read()
                .unwrap()
                .translate(LanguageKey::About)
                .clone()
        }),
        (&quit_i, &|| {
            LANGUAGE_MANAGER
                .read()
                .unwrap()
                .translate(LanguageKey::Quit)
                .clone()
        }),
    ];

    let mut should_poll = false;
    static POOL_INTERVAL: std::time::Duration = std::time::Duration::from_millis(500);
    let return_code = event_loop.run_return(|_event, _, control_flow| {
        // println!("event_loop");
        match should_poll {
            true => {
                *control_flow = ControlFlow::WaitUntil(std::time::Instant::now() + POOL_INTERVAL)
            }
            false => *control_flow = ControlFlow::Wait,
        }
        if let Ok(_) = mr.rx_reset_files_item.try_recv() {
            handle_menu_event_clear_files(&add_files_i, &clear_files_i);
            should_poll = false;
        }
        if let Ok(_) = mr.rx_close_allow_to_be_searched.try_recv() {
            allow_to_be_search_i.set_checked(false);
            should_poll = false;
        }
        // 不能一直阻塞在这里，否则右键点击托盘图标会没有反应
        if let Ok(event) = menu_channel.try_recv() {
            match event.id {
                id if id == sub_hide_once_i.id() => {
                    *control_flow = ControlFlow::ExitWithCode(ReturnCode::HideIcon as i32);
                }
                id if id == sub_hide_forever_i.id() => {
                    {
                        let mut config = config::GLOBAL_CONFIG.lock().unwrap();
                        config.show_systray_icon = false;
                        if let Err(err) = config.save() {
                            error!("save config error: {}", err);
                        }
                    }
                    *control_flow = ControlFlow::ExitWithCode(ReturnCode::HideIcon as i32);
                }
                id if id == lang_zh_i.id() => {
                    {
                        let mut config = config::GLOBAL_CONFIG.lock().unwrap();
                        config.language = Language::ZH;
                        if let Err(err) = config.save_and_set() {
                            error!("save config error: {}", err);
                        }
                    }
                    LANGUAGE_MANAGER.write().unwrap().set_language(Language::ZH);
                    switch_lang(items2);
                    lang_zh_i.set_checked(true);
                    lang_en_i.set_checked(false);
                }
                id if id == lang_en_i.id() => {
                    {
                        let mut config = config::GLOBAL_CONFIG.lock().unwrap();
                        config.language = Language::EN;
                        if let Err(err) = config.save_and_set() {
                            error!("save config error: {}", err);
                        }
                    }
                    LANGUAGE_MANAGER.write().unwrap().set_language(Language::EN);
                    switch_lang(items2);
                    lang_zh_i.set_checked(false);
                    lang_en_i.set_checked(true);
                }
                id if id == add_files_i.id() => {
                    let r = crate::RUNTIME.get().unwrap();
                    r.block_on(handle_menu_event_add_files(&add_files_i, &clear_files_i));
                    if clear_files_i.is_enabled() {
                        should_poll = true;
                    }
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
                id if id == allow_to_be_search_i.id() => {
                    let mut allow_to_be_search = config::ALLOW_TO_BE_SEARCHED.lock().unwrap();
                    *allow_to_be_search = !*allow_to_be_search;
                    info!("set allow_to_be_search: {}", *allow_to_be_search);
                    allow_to_be_search_i.set_checked(*allow_to_be_search);
                    should_poll = true;
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
            warn!("pick_files failed or canceled");
            return;
        }
    };
    let mut selected_files = SELECTED_FILES.get().unwrap().lock().unwrap();
    for file in files {
        debug!("selected file: {:?}", file);
        selected_files.insert(file.path().to_str().unwrap().to_string());
    }
    clear_item.set_enabled(true);
    add_item.set_text(format!(
        "{} - {}",
        LANGUAGE_MANAGER
            .read()
            .unwrap()
            .translate(LanguageKey::AddFiles),
        selected_files.len()
    ));
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
    if let Err(e) = clipboard_text {
        error!("get clipboard text error: {}", e);
        utils::inform(
            LANGUAGE_MANAGER
                .read()
                .unwrap()
                .translate(LanguageKey::ClipboardNotText),
            &PROGRAM_NAME,
        );
        return;
    }
    debug!("clipboard_text: {:?}", clipboard_text);
    let clipboard_text = clipboard_text.unwrap();
    let result = web::post_content_to_web(clipboard_text.as_bytes()).await;
    if let Err(e) = result {
        error!("post content to web error: {}", e);
        utils::inform(
            LANGUAGE_MANAGER
                .read()
                .unwrap()
                .translate(LanguageKey::PasteToWebFailed),
            &PROGRAM_NAME,
        );
        return;
    }
    utils::inform(
        LANGUAGE_MANAGER
            .read()
            .unwrap()
            .translate(LanguageKey::PasteToWebSuccess),
        &PROGRAM_NAME,
    );
}

async fn handle_menu_event_copy_from_web() {
    let result = web::get_content_from_web().await;
    if let Err(e) = result {
        error!("get content from web error: {}", e);
        utils::inform(
            LANGUAGE_MANAGER
                .read()
                .unwrap()
                .translate(LanguageKey::CopyFromWebFailed),
            &PROGRAM_NAME,
        );
        return;
    }
    let content = result.unwrap();
    let content = String::from_utf8(content);
    if let Err(_) = content {
        error!("content is not utf8");
        return;
    }
    let content = content.unwrap();
    debug!("content: {}", content);
    let result = config::CLIPBOARD.lock().unwrap().set_text(&content);
    if let Err(e) = result {
        error!("set clipboard text error: {}", e);
        return;
    }
    utils::inform(&content, &PROGRAM_NAME);
}

fn handle_menu_event_clear_files(add_item: &MenuItem, clear_item: &MenuItem) {
    {
        let mut selected_files = SELECTED_FILES.get().unwrap().lock().unwrap();
        selected_files.clear();
        selected_files.shrink_to_fit();
    }
    clear_item.set_enabled(false);
    add_item.set_text(format!(
        "{} - 0",
        LANGUAGE_MANAGER
            .read()
            .unwrap()
            .translate(LanguageKey::AddFiles),
    ));
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

trait SetTitle<S: AsRef<str>> {
    fn set_text(&self, text: S);
}
impl<S: AsRef<str>> SetTitle<S> for MenuItem {
    fn set_text(&self, text: S) {
        self.set_text(text.as_ref());
    }
}

impl<S: AsRef<str>> SetTitle<S> for Submenu {
    fn set_text(&self, text: S) {
        self.set_text(text.as_ref());
    }
}

impl<S: AsRef<str>> SetTitle<S> for PredefinedMenuItem {
    fn set_text(&self, text: S) {
        self.set_text(text.as_ref());
    }
}

impl<S: AsRef<str>> SetTitle<S> for CheckMenuItem {
    fn set_text(&self, text: S) {
        self.set_text(text.as_ref());
    }
}

fn switch_lang<S: AsRef<str>>(menus: &[(&dyn SetTitle<S>, &dyn Fn() -> S)]) {
    for menu in menus {
        menu.0.set_text(menu.1());
    }
}
