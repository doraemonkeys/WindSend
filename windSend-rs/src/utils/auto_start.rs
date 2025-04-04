#![allow(unused)]

use std::borrow::Cow;
use tracing::error;

pub struct StartHelper {
    exe_name: String,
    icon_relative_path: Option<String>,
}

impl StartHelper {
    pub fn new(exe_name: String) -> Self {
        Self {
            exe_name,
            icon_relative_path: None,
        }
    }
    pub fn set_icon_relative_path(mut self, icon_relative_path: String) -> Self {
        self.icon_relative_path = Some(icon_relative_path);
        self
    }

    pub fn set_auto_start(&self) -> Result<(), Box<dyn std::error::Error>> {
        // #[cfg(target_os = "windows")]
        // {
        //     self.set_win_auto_start()
        // }
        //  #[cfg(not(any(target_os = "linux", target_os = "windows", target_os = "macos")))]
        match std::env::consts::OS {
            "windows" => self.set_win_auto_start(),
            "macos" => self.set_mac_auto_start(),
            "linux" => self.set_linux_auto_start(),
            _ => Err(format!("unsupported os: {}", std::env::consts::OS).into()),
        }
    }

    pub fn unset_auto_start(&self) -> Result<(), Box<dyn std::error::Error>> {
        // #[cfg(target_os = "windows")]
        // {
        //     self.unset_win_auto_start()
        // }
        match std::env::consts::OS {
            "windows" => self.unset_win_auto_start(),
            "macos" => self.unset_mac_auto_start(),
            "linux" => self.unset_linux_auto_start(),
            _ => Err(format!("unsupported os: {}", std::env::consts::OS).into()),
        }
    }

    fn set_win_auto_start(&self) -> Result<(), Box<dyn std::error::Error>> {
        // C:\Users\*\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup
        // 获取当前Windows用户的home directory.
        let win_user_home_dir =
            home::home_dir().ok_or("failed to get current windows user home dir")?;
        let start_file = format!(
            r#"{}\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\{}_start.vbs"#,
            win_user_home_dir.to_str().unwrap(),
            self.exe_name
        );

        let path = std::env::current_dir().map_err(|err| {
            format!(
                "failed to get working directory : {}",
                err.to_string().replace('\\', "\\\\")
            )
        })?;
        let path = path.to_str().unwrap().replace('\\', "\\\\");

        let content = String::from(r#"Set objShell = CreateObject("WScript.Shell")"#)
            + "\r\n"
            + &format!(r#"objShell.CurrentDirectory = "{}""#, path)
            + "\r\n"
            + &format!(r#"objShell.Run "powershell /c .\\{}""#, self.exe_name)
            + ",0";
        let content_bytes = utf8_to_gbk(&content)?;
        let old_content = std::fs::read(&start_file).unwrap_or_default();
        if old_content == content_bytes {
            tracing::debug!("start_file content not changed, skip");
            return Ok(());
        }
        let mut file = std::fs::OpenOptions::new()
            .create(true)
            .truncate(true)
            .write(true)
            .open(&start_file)?;
        use std::io::Write;
        file.write_all(&content_bytes)?;
        Ok(())
    }

    fn set_mac_auto_start(&self) -> Result<(), Box<dyn std::error::Error>> {
        let home_dir = home::home_dir().ok_or("failed to get current user home dir")?;
        let start_file = format!(
            "{}/Library/LaunchAgents/{}_start.plist",
            home_dir.to_str().unwrap(),
            self.exe_name
        );
        let cur_path = std::env::current_dir().map_err(|err| {
            format!(
                "failed to get working directory : {}",
                err.to_string().replace('\\', "\\\\")
            )
        })?;

        /*
        TODO: 验证自启是否成功

         <key>WorkingDirectory</key>
         <string>/path/to/your/program/directory</string>

        */
        let mac_list_file = format!(
            r#"
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>{0}</string>
                <key>ProgramArguments</key>
                    <array>
                        <string>{1}</string>
                    </array>
                <key>RunAtLoad</key>
                <true/>
                <key>WorkingDirectory</key>
                <string>{2}</string>
                <key>StandardErrorPath</key>
                <string>/tmp/{0}_start.err</string>
                <key>StandardOutPath</key>
                <string>/tmp/{0}_start.out</string>
            </dict>
            </plist>
            "#,
            crate::MAC_APP_LABEL,
            cur_path
                .join(std::path::Path::new(&self.exe_name))
                .to_str()
                .unwrap(),
            cur_path.to_str().unwrap()
        );
        let old_content = std::fs::read(&start_file).unwrap_or_default();
        if old_content == mac_list_file.as_bytes() {
            tracing::debug!("start_file content not changed, skip");
            return Ok(());
        }
        let mut file = std::fs::OpenOptions::new()
            .create(true)
            .truncate(true)
            .write(true)
            .open(&start_file)?;
        use std::io::Write;
        file.write_all(mac_list_file.as_bytes())?;
        Ok(())
    }

    fn unset_win_auto_start(&self) -> Result<(), Box<dyn std::error::Error>> {
        let win_user_home_dir =
            home::home_dir().ok_or("failed to get current windows user home dir")?;
        let start_file = format!(
            r#"{}\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\{}_start.vbs"#,
            win_user_home_dir.to_str().unwrap(),
            self.exe_name
        );

        if !std::path::Path::new(&start_file).exists() {
            return Ok(());
        }

        std::fs::remove_file(&start_file)?;
        Ok(())
    }

    fn unset_mac_auto_start(&self) -> Result<(), Box<dyn std::error::Error>> {
        let home_dir = home::home_dir().ok_or("failed to get current user home dir")?;
        let start_file = format!(
            "{}/Library/LaunchAgents/{}_start.plist",
            home_dir.to_str().unwrap(),
            self.exe_name
        );
        if !std::path::Path::new(&start_file).exists() {
            return Ok(());
        }
        std::fs::remove_file(&start_file)?;
        Ok(())
    }

    fn set_linux_auto_start(&self) -> Result<(), Box<dyn std::error::Error>> {
        use std::{fs, path::Path};

        let autostart_dir = dirs::config_dir()
            .ok_or("Could not find config directory")?
            .join("autostart");

        fs::create_dir_all(&autostart_dir)?;

        let desktop_file_path = autostart_dir.join(format!("{}.desktop", self.exe_name));

        let executable_path = std::env::current_exe()?;

        let icon_path = self.icon_relative_path.as_ref().map(|relative_path| {
            let exe_dir = executable_path.parent().unwrap_or_else(|| Path::new(""));
            exe_dir.join(relative_path).display().to_string()
        });

        let mut desktop_file_content = String::new();
        desktop_file_content.push_str("[Desktop Entry]\n");
        desktop_file_content.push_str("Version=1.0\n");
        desktop_file_content.push_str("Type=Application\n");
        desktop_file_content.push_str(&format!("Name={}\n", self.exe_name));
        desktop_file_content.push_str(&format!("Comment={}\n", self.exe_name));
        desktop_file_content.push_str(&format!("Exec={}\n", executable_path.display()));
        desktop_file_content.push_str(&format!("Icon={}\n", icon_path.unwrap_or_default()));
        desktop_file_content.push_str("Terminal=false\n");
        desktop_file_content.push_str("StartupNotify=false\n");

        fs::write(desktop_file_path, desktop_file_content)?;

        Ok(())
    }

    fn unset_linux_auto_start(&self) -> Result<(), Box<dyn std::error::Error>> {
        let autostart_dir = dirs::config_dir()
            .ok_or("Could not find config directory")?
            .join("autostart");
        let desktop_file_path = autostart_dir.join(format!("{}.desktop", self.exe_name));
        if !desktop_file_path.exists() {
            return Ok(());
        }
        std::fs::remove_file(desktop_file_path)?;
        Ok(())
    }
}

// This function is only used in windows
#[allow(dead_code)]
pub fn utf8_to_gbk(b: &str) -> Result<Vec<u8>, Box<dyn std::error::Error>> {
    use encoding::all::GBK;
    use encoding::{EncoderTrap, Encoding};
    let content_bytes = GBK.encode(b, EncoderTrap::Strict)?;
    Ok(content_bytes)
}

/// Get the default desktop path of the system
pub fn get_desktop_path() -> Result<String, String> {
    let home_dir = home::home_dir().ok_or_else(|| "get home dir error".to_string())?;
    let desktop_path = home_dir.join("Desktop");
    if !desktop_path.exists() {
        return Err("desktop path not exist in home dir".to_string());
    }
    Ok(desktop_path.to_str().unwrap().to_string())
}
