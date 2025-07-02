#![allow(unused)]

use std::borrow::Cow;
use tracing::error;

/// 去除颜色
pub fn eliminate_color(line: &[u8]) -> Cow<'_, [u8]> {
    //"\033[31m 红色 \033[0m"
    if subslice::bmh::find(line, b"\x1b[0m").is_some() {
        let mut buf = Vec::with_capacity(line.len());
        let mut start = 0;
        let mut end;
        loop {
            if let Some(index) = subslice::bmh::find(&line[start..], b"\x1b[") {
                end = start + index;
                buf.extend_from_slice(&line[start..end]);
                // end的位置是\x1b的位置，end + 3 与 end + 4 一个是\x1b[0m，一个是\x1b[31m，以此类推，
                // 如果 end + 4 <= line.len()或者end + 5 <= line.len() 都不成立，
                // 说明字符串含有\x1b，但是\x1b[0m或者\x1b[31m不完整，或许不是颜色字符串。
                // if end + 3 < line.len() && line[end + 3] == 'm' as u8 {
                //     start = end + 4;
                // } else if end + 4 < line.len() && line[end + 4] == 'm' as u8 {
                //     start = end + 5;
                // } else if end + 5 < line.len() && line[end + 5] == 'm' as u8 {
                //     start = end + 6;
                // } else if end + 6 < line.len() && line[end + 6] == 'm' as u8 {
                //     start = end + 7;
                // } else {
                //     println!("WARN: line[end + 3] != 'm' as u8 && line[end + 4] != 'm' as u8");
                //     return line.to_vec();
                // }
                let mut temp_index = end + 3;
                while temp_index < line.len() && temp_index <= end + 6 {
                    if line[temp_index] == b'm' {
                        start = temp_index + 1;
                        break;
                    }
                    temp_index += 1;
                }
                if temp_index == line.len() || temp_index > end + 6 {
                    println!("WARN: 'm' not found in line[{}..{}]", end + 3, end + 6);
                    return Cow::Owned(line.to_vec());
                }
                if start == line.len() {
                    break;
                }
                if start > line.len() {
                    println!("WARN: start: {} > line.len(): {}", start, line.len());
                    return Cow::Owned(line.to_vec());
                }
            } else {
                buf.extend_from_slice(&line[start..]);
                break;
            }
        }
        return Cow::Owned(buf);
    }
    Cow::Borrowed(line)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn test_eliminate_color() {
        let line = "\x1b[31m 红色 \x1b[0m";
        println!("origin line: {}", line);
        let line = eliminate_color(line.as_bytes());
        println!("eliminate_color: {}", String::from_utf8_lossy(&line));
        assert_eq!(line, " 红色 ".as_bytes());

        struct TestCase {
            name: &'static str,
            origin: &'static str,
            expected: &'static str,
        }
        let test_cases = vec![
            TestCase {
                name: "test1",
                origin: "\x1b[31m 红色 \x1b[0m",
                expected: " 红色 ",
            },
            TestCase {
                name: "test2",
                origin: "\x1b[31m 红色 \x1b[0m\x1b[31m 红色 \x1b[0m",
                expected: " 红色  红色 ",
            },
            TestCase {
                name: "test3",
                origin: "\x1b[31m 红色 \x1b[0m\x1b[31m 红色 \x1b[0m\x1b[31m 红色 \x1b[0m",
                expected: " 红色  红色  红色 ",
            },
            TestCase {
                name: "test4",
                origin: "你好\x1b[31m 红色 \x1b[0m",
                expected: "你好 红色 ",
            },
            TestCase {
                name: "test5",
                origin: "你好\x1b[2m 不知道啥色 \x1b[0m",
                expected: "你好 不知道啥色 ",
            },
            TestCase {
                name: "test6",
                origin: "你好\x1b[2m 不知道啥色 \x1b[0m 世界！！！",
                expected: "你好 不知道啥色  世界！！！",
            },
            TestCase {
                name: "test7",
                origin: "你好\x1b[101m 不知道啥色 \x1b[0m 世界！！！",
                expected: "你好 不知道啥色  世界！！！",
            },
            TestCase {
                name: "test8",
                origin: "你好\x1b[1001m 不知道啥色 \x1b[0m 世界！！！",
                expected: "你好 不知道啥色  世界！！！",
            },
            TestCase {
                name: "test9",
                origin: "你好 红色，hello world",
                expected: "你好 红色，hello world",
            },
        ];
        for test_case in test_cases {
            let line = eliminate_color(test_case.origin.as_bytes());
            println!(
                "origin: {}, eliminate_color: {}",
                test_case.origin,
                String::from_utf8_lossy(&line)
            );
            assert_eq!(line, test_case.expected.as_bytes(), "{}", test_case.name);
        }
    }
}

#[cfg(not(feature = "disable-systray-support"))]
pub fn open_url(uri: &str) -> Result<(), Box<dyn std::error::Error>> {
    match std::env::consts::OS {
        "windows" => {
            let mut cmd = std::process::Command::new("cmd")
                .args(["/c", "start", uri])
                .spawn()?;
            cmd.wait()?;
        }
        "macos" => {
            let mut cmd = std::process::Command::new("open").arg(uri).spawn()?;
            cmd.wait()?;
        }
        "linux" => {
            let mut cmd = std::process::Command::new("xdg-open").arg(uri).spawn()?;
            cmd.wait()?;
        }
        _ => {
            return Err(format!(
                "don't know how to open things on {} platform",
                std::env::consts::OS
            )
            .into());
        }
    }
    Ok(())
}

#[cfg(target_os = "macos")]
static INFORM_INIT_ONCE: std::sync::Once = std::sync::Once::new();

pub fn inform<T: AsRef<str>>(
    content: T,
    title: &str,
    #[cfg(target_os = "windows")] click_open: Option<&str>,
    #[cfg(not(target_os = "windows"))] _: Option<&str>,
) {
    let show_len = 80;
    let mut content_runes = content
        .as_ref()
        .char_indices()
        .filter_map(|ic| match ic.1 {
            c if !c.is_control() => Some(ic.1),
            _ => None,
        })
        .collect::<Vec<char>>();
    if content_runes.len() >= show_len {
        content_runes.truncate(show_len);
        content_runes.append(&mut vec!['.'; 3])
    }
    let body = content_runes.into_iter().collect::<String>();
    #[cfg(not(target_os = "windows"))]
    {
        #[cfg(target_os = "macos")]
        INFORM_INIT_ONCE.call_once(|| {
            use notify_rust::{get_bundle_identifier_or_default, set_application};
            let id = get_bundle_identifier_or_default("WindSend");
            if let Err(e) = set_application(&id) {
                tracing::error!("set_application id err:{}", e);
            }
        });
        use notify_rust::Notification;
        let mut n = Notification::new();
        n.summary(title).body(&body).appname("WindSend");
        #[cfg(not(target_os = "macos"))]
        n.icon(&crate::config::APP_ICON_PATH);

        n.show()
            .map_err(|err| error!("show notification error: {}", err))
            .ok();
    }
    #[cfg(target_os = "windows")]
    {
        use win_toast_notify::{CropCircle, Duration, WinToastNotify};
        let mut notify = WinToastNotify::new()
            // .set_app_id(crate::PROGRAM_NAME)
            .set_logo(&crate::config::APP_ICON_PATH, CropCircle::False)
            .set_title(title)
            .set_messages(vec![&body])
            .set_duration(Duration::Short);
        if let Some(click_open) = click_open {
            notify = notify.set_open(click_open);
        }
        if let Err(err) = notify.show() {
            error!("show notification error: {}", err);
        }
    }
}

#[cfg(target_os = "windows")]
pub fn inform_with_progress(click_open: Option<&str>, progress: win_toast_notify::Progress) {
    use win_toast_notify::{CropCircle, Duration, WinToastNotify};
    // println!("click_open: {:?}, progress: {:?}", click_open, progress);
    let save_path = crate::config::GLOBAL_CONFIG
        .read()
        .unwrap()
        .save_path
        .clone();
    let mut notify = WinToastNotify::new()
        // .set_app_id(crate::PROGRAM_NAME)
        .set_logo(&crate::config::APP_ICON_PATH, CropCircle::False)
        .set_title(crate::PROGRAM_NAME)
        .set_messages(vec![&format!(
            "{}: {}",
            crate::language::LanguageKey::SavePath.translate(),
            save_path
        )])
        .set_duration(Duration::Short)
        .set_progress(
            &progress.tag,
            &progress.title,
            &progress.status,
            progress.value,
            &progress.value_string,
        );
    if let Some(click_open) = click_open {
        notify = notify.set_open(click_open);
    }
    if let Err(err) = notify.show() {
        error!("show notification error: {}", err);
    }
}

pub fn has_img_ext(name: &str) -> bool {
    let ext = name.split('.').next_back().unwrap_or("");
    // match ext.to_lowercase().as_str() {
    //     "jpg" | "jpeg" | "png" | "gif" | "bmp" | "webp" | "ico" => true,
    //     _ => false,
    // }
    matches!(
        ext.to_lowercase().as_str(),
        "jpg" | "jpeg" | "png" | "gif" | "bmp" | "webp" | "ico"
    )
}

// e.g. zh_CN.UTF-8 => zh_CN
pub fn get_system_lang() -> String {
    let env_keys = vec!["LANG", "LC_ALL", "LC_MESSAGES", "LANGUAGE"];
    let mut lang = String::new();
    for key in env_keys {
        lang = std::env::var(key).unwrap_or_default();
        if !lang.is_empty() {
            break;
        }
    }
    #[cfg(target_os = "windows")]
    if lang.is_empty() {
        if let Ok(output) = std::process::Command::new("cmd")
            .args(["/c", "chcp"])
            .output()
        {
            match String::from_utf8_lossy(&output.stdout) {
                s if s.contains("936") => lang = "zh_CN".to_string(),
                s if s.contains("437") => lang = "en_US".to_string(),
                _ => {}
            }
        }
    }
    lang
}

/// Generate a unique file path, if the file already exists, add a number to the file name
pub fn generate_unique_filepath(path: impl AsRef<std::path::Path>) -> std::io::Result<String> {
    if !path.as_ref().exists() {
        let ret = path
            .as_ref()
            .to_str()
            .ok_or_else(|| std::io::Error::other("path to str error"))?;
        return Ok(ret.to_string());
    }
    let path = path.as_ref();
    let dir = path
        .parent()
        .ok_or_else(|| std::io::Error::other("path parent error"))?;
    let name = path
        .file_name()
        .ok_or_else(|| std::io::Error::other("path file_name error"))?;
    let name: String = name.to_string_lossy().to_string();
    let file_ext = path
        .extension()
        .unwrap_or(std::ffi::OsStr::new(""))
        .to_str()
        .unwrap_or("")
        .to_string();
    for i in 1..100 {
        let new_name = if !file_ext.is_empty() {
            let name = name.trim_end_matches(&format!(".{file_ext}"));
            format!("{name}({i}).{file_ext}")
        } else {
            format!("{name}({i})")
        };
        let new_path = dir.join(new_name);
        if !new_path.exists() {
            return Ok(new_path
                .to_str()
                .ok_or_else(|| std::io::Error::other("path to str error"))?
                .to_string());
        }
    }
    Err(std::io::Error::other(
        "generate unique filepath error, too many files",
    ))
}

pub trait ToFloat64 {
    fn to_f64(&self) -> Option<f64>;
}

macro_rules! impl_to_float64 {
    ($($t:ty),*) => {
        $(
            impl ToFloat64 for $t {
                fn to_f64(&self) -> Option<f64> {
                    Some(*self as f64)
                }
            }
        )*
    };
}

impl_to_float64!(u8, u16, u32, u64, u128, i32, i64, f64, f32);

#[allow(dead_code)]
pub fn bytes_to_human_readable<T>(bytes: T) -> String
where
    T: ToFloat64 + std::fmt::Display,
{
    const KB: f64 = 1024.0;
    const MB: f64 = KB * 1024.0;
    const GB: f64 = MB * 1024.0;
    const TB: f64 = GB * 1024.0;

    let bytes_f64 = bytes.to_f64().unwrap_or(0.0);

    if bytes_f64 >= TB {
        format!("{:.2} TB", bytes_f64 / TB)
    } else if bytes_f64 >= GB {
        format!("{:.2} GB", bytes_f64 / GB)
    } else if bytes_f64 >= MB {
        format!("{:.2} MB", bytes_f64 / MB)
    } else if bytes_f64 >= KB {
        format!("{:.2} KB", bytes_f64 / KB)
    } else {
        format!("{bytes} B")
    }
}

pub trait NormalizePath {
    /// Converts a given path to use the system's main separator.
    ///
    /// This function replaces all occurrences of backslashes (`\`) and forward slashes (`/`)
    /// in the input path with the system's main separator, which is platform-dependent.
    /// For example, on Windows, the main separator is `\`, and on Unix-like systems, it is `/`.
    ///
    /// # Examples
    ///
    /// ```
    /// use NormalizePath;
    /// let path = "some\\path/to\\convert";
    /// #[cfg(target_os = "linux")]
    /// assert_eq!(path.normalize_path(), "some/path/to/convert");
    /// #[cfg(target_os = "windows")]
    /// assert_eq!(path.normalize_path(), "some\\path\\to\\convert");
    /// ```
    fn normalize_path(&self) -> String;
}

impl<T: ?Sized + AsRef<str>> NormalizePath for T {
    fn normalize_path(&self) -> String {
        let separator = std::path::MAIN_SEPARATOR.to_string();
        self.as_ref().replace(['\\', '/'], &separator)
    }
}

pub fn log_path_info() {
    use tracing::{error, info};
    match std::env::current_exe() {
        Ok(path) => info!("Current executable path: {:?}", path),
        Err(e) => error!("Failed to get current executable path: {}", e),
    };
    match std::env::current_dir() {
        Ok(path) => info!("Current directory path: {:?}", path),
        Err(e) => error!("Failed to get current directory path: {}", e),
    }
}
