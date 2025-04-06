use lazy_static::lazy_static;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::RwLock;

#[derive(Hash, Eq, PartialEq, Clone, Default, Copy, Debug, Serialize, Deserialize)]
pub enum Language {
    #[default]
    #[serde(rename = "zh")]
    ZH,
    #[serde(rename = "en")]
    EN,
}

impl std::str::FromStr for Language {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        let s = s.to_lowercase();
        match s {
            s if s.starts_with(&Language::ZH.to_str().to_lowercase()) => Ok(Language::ZH),
            s if s.starts_with(&Language::EN.to_str().to_lowercase()) => Ok(Language::EN),
            _ => Err(format!("unknown language: {}", s)),
        }
    }
}

impl Language {
    // pub fn get_all() -> Vec<Language> {
    //     vec![Language::ZH, Language::EN]
    // }
    pub fn to_str(self) -> &'static str {
        match self {
            Language::ZH => "zh",
            Language::EN => "en",
        }
    }
}

#[derive(Hash, Eq, PartialEq, Clone, Copy)]
pub enum LanguageKey {
    AddFiles,
    ClearFiles,
    Copy,
    Paste,
    SavePath,
    HideIcon,
    OnlyOnce,
    HideForever,
    AutoStart,
    QuickPair,
    QuickPairTip,
    OpenOfficialWebsite,
    Quit,
    SelectFileFailed,
    SelectDirFailed,
    SaveConfigFailed,
    ClipboardNotText,
    PasteToWebSuccess,
    PasteToWebFailed,
    CopyFromWebFailed,
    ClipboardIsEmpty,
    DirCreated,
    About,
    NFilesSavedTo,
    VerifySuccess,
    CopySuccessfully,
    EffectiveAfterRestart,
    DirCreatedSuccessfully,
    RelayConnected,
    RelayServerNotConnected,
    RelayDisabled,
}

impl LanguageKey {
    pub fn translate(&self) -> &'static String {
        LANGUAGE_MANAGER.read().unwrap().translate(*self)
    }
}

lazy_static! {
    static ref EN_US: HashMap<LanguageKey, String> = vec![
        (LanguageKey::AddFiles, String::from("Add Files")),
        (LanguageKey::ClearFiles, String::from("Clear Files")),
        (LanguageKey::Copy, String::from("Copy")),
        (LanguageKey::Paste, String::from("Paste")),
        (LanguageKey::SavePath, String::from("Save Path")),
        (LanguageKey::HideIcon, String::from("Hide Icon")),
        (LanguageKey::OnlyOnce, String::from("Only Once")),
        (LanguageKey::HideForever, String::from("Hide Forever")),
        (LanguageKey::AutoStart, String::from("Auto Start")),
        (LanguageKey::QuickPair, String::from("Quick Pair")),
        (
            LanguageKey::QuickPairTip,
            String::from("Quick Pair will be closed automatically after successful pairing")
        ),
        (
            LanguageKey::OpenOfficialWebsite,
            String::from("Open Website")
        ),
        (LanguageKey::Quit, String::from("Quit")),
        (
            LanguageKey::SelectFileFailed,
            String::from("Select File Failed")
        ),
        (
            LanguageKey::SelectDirFailed,
            String::from("Select Dir Failed")
        ),
        (
            LanguageKey::SaveConfigFailed,
            String::from("Save Config Failed")
        ),
        (
            LanguageKey::ClipboardNotText,
            String::from("Clipboard content is not text")
        ),
        (
            LanguageKey::PasteToWebSuccess,
            String::from("Successfully pasted to web")
        ),
        (
            LanguageKey::PasteToWebFailed,
            String::from("Failed to paste to web")
        ),
        (
            LanguageKey::CopyFromWebFailed,
            String::from("Failed to copy text from web")
        ),
        (
            LanguageKey::ClipboardIsEmpty,
            String::from("You haven't copied anything yet")
        ),
        (
            LanguageKey::DirCreated,
            String::from("Directory created successfully")
        ),
        (LanguageKey::About, String::from("About")),
        (LanguageKey::NFilesSavedTo, String::from("files saved to")),
        (LanguageKey::VerifySuccess, String::from("Verify Success")),
        (
            LanguageKey::CopySuccessfully,
            String::from("Copy Successfully")
        ),
        (
            LanguageKey::EffectiveAfterRestart,
            String::from("Effective after restart")
        ),
        (
            LanguageKey::DirCreatedSuccessfully,
            String::from("Directory created successfully")
        ),
        (LanguageKey::RelayConnected, String::from("Relay Connected")),
        (
            LanguageKey::RelayServerNotConnected,
            String::from("Relay Disconnected")
        ),
        (LanguageKey::RelayDisabled, String::from("Relay Disabled")),
    ]
    .into_iter()
    .collect();
}

lazy_static! {
    static ref ZH_CN: HashMap<LanguageKey, String> = vec![
        (LanguageKey::AddFiles, String::from("添加文件")),
        (LanguageKey::ClearFiles, String::from("清空文件")),
        (LanguageKey::Copy, String::from("复制")),
        (LanguageKey::Paste, String::from("粘贴")),
        (LanguageKey::SavePath, String::from("文件保存路径")),
        (LanguageKey::HideIcon, String::from("隐藏图标")),
        (LanguageKey::OnlyOnce, String::from("仅一次")),
        (LanguageKey::HideForever, String::from("永久隐藏")),
        (LanguageKey::AutoStart, String::from("开机自启")),
        (LanguageKey::QuickPair, String::from("快速配对")),
        (
            LanguageKey::QuickPairTip,
            String::from("快速配对将在第一次成功后自动关闭")
        ),
        (LanguageKey::OpenOfficialWebsite, String::from("打开官网")),
        (LanguageKey::Quit, String::from("退出")),
        (LanguageKey::SelectFileFailed, String::from("选择文件失败")),
        (LanguageKey::SelectDirFailed, String::from("选择文件夹失败")),
        (LanguageKey::SaveConfigFailed, String::from("保存配置失败")),
        (
            LanguageKey::ClipboardNotText,
            String::from("当前剪切板内容不是文本")
        ),
        (
            LanguageKey::PasteToWebSuccess,
            String::from("粘贴到web成功")
        ),
        (LanguageKey::PasteToWebFailed, String::from("粘贴到web失败")),
        (
            LanguageKey::CopyFromWebFailed,
            String::from("从web复制文本失败")
        ),
        (
            LanguageKey::ClipboardIsEmpty,
            String::from("你还没有复制任何内容")
        ),
        (LanguageKey::DirCreated, String::from("文件夹创建成功")),
        (LanguageKey::About, String::from("关于")),
        (LanguageKey::NFilesSavedTo, String::from("个文件已保存到")),
        (LanguageKey::VerifySuccess, String::from("验证成功")),
        (LanguageKey::CopySuccessfully, String::from("复制成功")),
        (
            LanguageKey::EffectiveAfterRestart,
            String::from("重启后生效")
        ),
        (
            LanguageKey::DirCreatedSuccessfully,
            String::from("文件夹创建成功")
        ),
        (LanguageKey::RelayConnected, String::from("中转已连接")),
        (
            LanguageKey::RelayServerNotConnected,
            String::from("中转未连接")
        ),
        (LanguageKey::RelayDisabled, String::from("中转未启用")),
    ]
    .into_iter()
    .collect();
}

lazy_static! {
    pub static ref LANGUAGE_MANAGER: RwLock<LanguageManager> = RwLock::new(LanguageManager::new());
}

pub struct LanguageManager {
    cur_lang: Language,
}

impl LanguageManager {
    fn new() -> Self {
        Self {
            cur_lang: Language::ZH,
        }
    }

    pub fn set_language(&mut self, lang: Language) {
        self.cur_lang = lang;
    }

    #[allow(dead_code)]
    pub fn get_language(&self) -> Language {
        self.cur_lang
    }

    pub fn translate(&self, key: LanguageKey) -> &'static String {
        match self.cur_lang {
            Language::ZH => ZH_CN.get(&key).unwrap(),
            Language::EN => EN_US.get(&key).unwrap(),
        }
    }
}

#[warn(dead_code)]
pub fn translate(key: LanguageKey) -> &'static String {
    LANGUAGE_MANAGER.read().unwrap().translate(key)
}
