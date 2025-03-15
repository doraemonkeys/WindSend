use crate::utils;
use image::EncodableLayout;
use lazy_static::lazy_static;
use serde::{Deserialize, Serialize};
use std::sync::{Mutex, RwLock};
use std::{path::Path, str::FromStr};
use tracing::{debug, error, warn};
use utils::clipboard::ClipboardManager;

use std::path::PathBuf;
use dirs;

// 配置文件路径
lazy_static! {
    pub static ref CONFIG_FILE_PATH: PathBuf = {
        #[cfg(target_os = "macos")]
        {
            dirs::data_local_dir().unwrap()
                .join("Windsend/config.yaml")
        }
        #[cfg(not(target_os = "macos"))]
        {
            PathBuf::from("config.yaml")
        }
    };
}

// TLS目录
lazy_static! {
    pub static ref TLS_DIR: PathBuf = {
        #[cfg(target_os = "macos")]
        {
            dirs::data_local_dir().unwrap()
                .join("Windsend/tls")
        }
        #[cfg(not(target_os = "macos"))]
        {
            PathBuf::from("./tls")
        }
    };
}

// TLS证书文件路径
pub static TLS_CERT_FILE: &str = "cert.pem";
pub static TLS_KEY_FILE: &str = "key.pem";
pub static TLS_CA_CERT_FILE: &str = "ca_cert.pem";
pub static TLS_CA_KEY_FILE: &str = "ca_key.pem";

// 图标路径处理
pub static APP_ICON_NAME :&str ="icon-192.png";

mod mac_utils {
    pub fn get_resource_dir() -> String {
        #[cfg(target_os = "macos")]
    {
        // 获取当前可执行文件的路径
        let exe_path = std::env::current_exe().unwrap();
        // 获取应用程序包的根目录
        let bundle_path = exe_path
            .parent()  // 可执行文件所在目录
            .and_then(|p| p.parent())  // Contents 目录
            .and_then(|p| p.parent())  // .app 目录
            .unwrap_or_else(||std::path::Path::new("./"));
        // 构建资源目录路径
        let resource_dir = bundle_path.join("Contents/Resources");
        resource_dir.display().to_string()
    }
        #[cfg(not(target_os = "macos"))]
        {
            // 获取当前程序的工作目录
            std::env::current_dir().unwrap_or_else(|_| std::path::PathBuf::from("./")).display().to_string()
        }
    }
}

 
    

// 日志目录
lazy_static! {
    pub static ref DEFAULT_LOG_DIR: PathBuf = {
        #[cfg(target_os = "macos")]
        {
            dirs::home_dir().unwrap().join("Library/Logs/Windsend/logs")
        }
        #[cfg(not(target_os = "macos"))]
        {
            PathBuf::from("./logs")
        }
    };
}

///////////

pub static APP_ICON_PATH: std::sync::OnceLock<String> = std::sync::OnceLock::new();

lazy_static! {
    static ref START_HELPER: utils::StartHelper =
        utils::StartHelper::new(crate::PROGRAM_NAME.to_string())
            .set_icon_relative_path(APP_ICON_NAME.to_string());
}
lazy_static! {
    pub static ref GLOBAL_CONFIG: RwLock<Config> = RwLock::new(init_global_config());
    pub static ref LOG_LEVEL: tracing::Level = GLOBAL_CONFIG
        .read()
        .map(|config| config
            .log_level
            .parse::<tracing::Level>()
            .unwrap_or(tracing::Level::INFO))
        .unwrap_or(tracing::Level::INFO);
}
lazy_static! {
    pub static ref ALLOW_TO_BE_SEARCHED: Mutex<bool> = Mutex::new(false);
}

pub fn get_cryptor() -> Result<utils::encrypt::AESCbcFollowedCrypt, Box<dyn std::error::Error>> {
    let cryptor = utils::encrypt::AESCbcFollowedCrypt::new(
        hex::decode(GLOBAL_CONFIG.read()?.secret_key_hex.clone())?.as_bytes(),
    )?;
    Ok(cryptor)
}
lazy_static! {
    pub static ref CLIPBOARD: ClipboardManager = ClipboardManager::new()
        .inspect_err(|err| {
            error!("init clipboard error: {}", err);
        })
        .unwrap();
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Config {
    #[serde(rename = "serverPort")]
    pub server_port: String,
    #[serde(rename = "secretKeyHex")]
    pub secret_key_hex: String,
    #[serde(rename = "showToolbarIcon")]
    pub show_systray_icon: bool,
    #[serde(rename = "autoStart")]
    pub auto_start: bool,
    #[serde(rename = "savePath")]
    pub save_path: String,
    #[serde(rename = "language")]
    pub language: crate::language::Language,
    #[serde(rename = "logLevel", default)]
    pub log_level: String,
    // Allow to be searched once after the program starts
    #[serde(rename = "allowToBeSearchedOnce")]
    #[serde(default)]
    pub allow_to_be_searched_once: bool,
    /// External NAT address of the local machine, other devices may access the local machine through this address
    #[serde(rename = "externalIPs")]
    pub external_ips: Option<Vec<String>>,
    /// Trusted remote host
    #[serde(rename = "trustedRemoteHosts", default)]
    pub trusted_remote_hosts: Option<Vec<String>>,
}

#[cfg(not(feature = "disable-systray-support"))]
fn default_allow_to_be_searched_once() -> bool {
    false
}

#[cfg(feature = "disable-systray-support")]
fn default_allow_to_be_searched_once() -> bool {
    true
}

impl Config {
    pub fn empty_check(&self) -> Result<(), String> {
        if self.server_port.is_empty() {
            return Err("server_port is empty".to_string());
        }
        if self.secret_key_hex.is_empty() {
            return Err("secret_key_hex is empty".to_string());
        }
        Ok(())
    }
    pub fn save(&self) -> Result<(), String> {
        self.empty_check()?;
        let file = std::fs::File::create(&*CONFIG_FILE_PATH)
            .map_err(|err| format!("create config file error: {}", err))?;
        serde_yaml::to_writer(file, self)
            .map_err(|err| format!("write config file error: {}", err))?;
        Ok(())
    }
    pub fn save_and_set(&self) -> Result<(), String> {
        self.empty_check()?;
        self.set()?;
        self.save()
    }
    pub fn set(&self) -> Result<(), String> {
        self.empty_check()?;
        #[cfg(not(all(target_os = "linux", feature = "disable-systray-support")))]
        if self.auto_start {
            if let Err(e) = START_HELPER.set_auto_start() {
                return Err(format!("set_auto_start error: {}", e));
            }
        } else if let Err(e) = START_HELPER.unset_auto_start() {
            return Err(format!("unset_auto_start error: {}", e));
        }

        crate::language::LANGUAGE_MANAGER
            .write()
            .unwrap()
            .set_language(self.language);

        Ok(())
    }

    fn generate_default() -> Self {
        let lang = crate::utils::get_system_lang();
        let lang = crate::language::Language::from_str(&lang);
        Self {
            server_port: "6779".to_string(),
            secret_key_hex: utils::encrypt::generate_secret_key_hex(32),
            show_systray_icon: true,
            auto_start: false,
            save_path: utils::get_desktop_path().unwrap_or_else(|err| {
                warn!("get_desktop_path error: {}", err);
                "./".to_string()
            }),
            language: lang.unwrap_or_default(),
            log_level: "INFO".to_string(),
            allow_to_be_searched_once: default_allow_to_be_searched_once(),
            external_ips: None,
            trusted_remote_hosts: Some(vec![
                "127.0.0.1".to_string(),
                "localhost".to_string(),
                "::1".to_string(),
            ]),
        }
    }
}

fn init_global_config() -> Config {
     // 确保配置目录存在
     print!("Ensuring config directory exists: {:?}", &*CONFIG_FILE_PATH);
     if let Some(parent_dir) = CONFIG_FILE_PATH.parent() {
        if !parent_dir.exists() {
            if let Err(err) = std::fs::create_dir_all(parent_dir) {
                panic!("Failed to create config directory: {}", err);
            }
        }
    }


    if !CONFIG_FILE_PATH.exists() {
        let cnf = Config::generate_default();
        if let Err(err) = cnf.save_and_set() {
            panic!("init_global_config error: {}", err);
        }
        return cnf;
    }
    let file = std::fs::File::open(&*CONFIG_FILE_PATH).unwrap();
    let cnf = serde_yaml::from_reader(file);
    if let Err(err) = cnf {
        panic!("deserialize config file error: {}", err);
    }
    let cnf: Config = cnf.unwrap();
    if let Err(err) = cnf.set() {
        panic!("init_global_config error: {}", err);
    }

    if cnf.allow_to_be_searched_once {
        *crate::config::ALLOW_TO_BE_SEARCHED.lock().unwrap() = true;
    }

    // dbg!(&cnf);

    cnf
}

struct LogWriter(tracing_appender::rolling::RollingFileAppender);

impl LogWriter {
    pub fn new(file_appender: tracing_appender::rolling::RollingFileAppender) -> Self {
        Self(file_appender)
    }
}

impl std::io::Write for LogWriter {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        self.0.write_all(&utils::eliminate_color(buf))?;
        if *LOG_LEVEL >= tracing::Level::DEBUG {
            std::io::stdout().write_all(buf)?;
        }
        Ok(buf.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        self.0.flush()?;
        if *LOG_LEVEL >= tracing::Level::DEBUG {
            std::io::stdout().flush()?;
        }
        Ok(())
    }
}

pub fn init() {
    init_global_logger(*LOG_LEVEL);

    let _current_dir = std::env::current_dir().unwrap_or(std::path::PathBuf::from("./"));
    let icon_path = format!("{}/{}", mac_utils::get_resource_dir(), APP_ICON_NAME);
    debug!("icon_path: {:?}", icon_path);
    APP_ICON_PATH.set(icon_path).unwrap();

    init_tls_config();
}

fn init_global_logger(log_level: tracing::Level) {
    let file_appender =
        tracing_appender::rolling::never(&*DEFAULT_LOG_DIR, format!("{}.log", crate::PROGRAM_NAME));
    let log_writer = LogWriter::new(file_appender);
    let (non_blocking_appender, writer_guard) = tracing_appender::non_blocking(log_writer);
    // let subscriber = tracing_subscriber::FmtSubscriber::builder()
    //     .with_max_level(*LOG_LEVEL)
    //     .with_line_number(true)
    //     .with_writer(non_blocking_appender)
    //     .with_timer(tracing_subscriber::fmt::time::LocalTime::rfc_3339())
    //     .finish();
    // tracing::subscriber::set_global_default(subscriber).unwrap();
    // Box::leak(Box::new(writer_guard));

    use tracing_subscriber::{
        filter::EnvFilter, fmt, layer::SubscriberExt, util::SubscriberInitExt,
    };
    let filter = tracing_subscriber::filter::EnvFilter::try_from_default_env()
        .or_else(|_| EnvFilter::try_new(log_level.to_string()))
        .unwrap()
        // 屏蔽掉reqwest的日志
        .add_directive("reqwest=off".parse().unwrap())
        // 屏蔽掉hyper的日志(设置等级为info)
        .add_directive("hyper=info".parse().unwrap())
        .add_directive("rustls=error".parse().unwrap());
    let fmt_layer = fmt::layer()
        // .pretty()
        .with_line_number(true)
        .with_writer(non_blocking_appender)
        .with_timer(tracing_subscriber::fmt::time::LocalTime::rfc_3339());

    tracing_subscriber::Registry::default()
        .with(filter)
        .with(fmt_layer)
        .init();
    Box::leak(Box::new(writer_guard));
    tracing::info!("init_global_logger success");
}

fn init_tls_config() {
    // mkdir tls
    if !Path::new(&*TLS_DIR).exists() {
        std::fs::create_dir(&*TLS_DIR).unwrap();
    }
    let cert_path = Path::new(&*TLS_DIR).join(TLS_CERT_FILE);
    let key_path = Path::new(&*TLS_DIR).join(TLS_KEY_FILE);
    let ca_cert_path = Path::new(&*TLS_DIR).join(TLS_CA_CERT_FILE);
    let ca_key_path = Path::new(&*TLS_DIR).join(TLS_CA_KEY_FILE);
    // Remove them, for easy debugging
    // std::fs::remove_file(&cert_path).ok();
    // std::fs::remove_file(&key_path).ok();
    // check file
    if !cert_path.exists() || !key_path.exists() || !ca_cert_path.exists() || !ca_key_path.exists()
    {
        let result = utils::tls::generate_ca_and_signed_certificate_pair();
        if let Err(err) = result {
            panic!("init_tls_config error: {}", err);
        }
        let ([cert_pem, priv_pem], [ca_cert_pem, ca_key_pem]) = result.unwrap();
        std::fs::write(cert_path, cert_pem).unwrap();
        std::fs::write(key_path, priv_pem).unwrap();
        std::fs::write(ca_cert_path, ca_cert_pem).unwrap();
        std::fs::write(ca_key_path, ca_key_pem).unwrap();
    }
}

pub fn read_ca_certificate_pem() -> std::io::Result<String> {
    std::fs::read_to_string(Path::new(&*TLS_DIR).join(TLS_CA_CERT_FILE))
}

pub fn get_tls_acceptor() -> Result<tokio_rustls::TlsAcceptor, Box<dyn std::error::Error>> {
    use tokio_rustls::rustls;
    use tokio_rustls::rustls::pki_types::PrivateKeyDer;
    let private_key_bytes = std::fs::read(Path::new(&*TLS_DIR).join(TLS_KEY_FILE))?;
    let mut private_key: Option<PrivateKeyDer<'static>> = None;

    let pkcs8_private_key =
        rustls_pemfile::pkcs8_private_keys(&mut private_key_bytes.as_slice()).next();
    if let Some(Ok(pkcs8_private_key)) = pkcs8_private_key {
        private_key = Some(pkcs8_private_key.into());
    }
    if private_key.is_none() {
        let rsa_private_key =
            rustls_pemfile::rsa_private_keys(&mut private_key_bytes.as_slice()).next();
        let rsa_private_key = rsa_private_key.ok_or("rsa_private_key is none")??;
        private_key = Some(rsa_private_key.into());
    }
    let private_key = private_key.unwrap();

    let ca_cert_bytes = std::fs::read(Path::new(&*TLS_DIR).join(TLS_CERT_FILE))?;
    let ca_cert = rustls_pemfile::certs(&mut ca_cert_bytes.as_slice())
        .next()
        .ok_or("ca_cert is none")??;

    let server_conf = rustls::ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(vec![ca_cert], private_key)?;
    Ok(tokio_rustls::TlsAcceptor::from(std::sync::Arc::new(
        server_conf,
    )))
}
