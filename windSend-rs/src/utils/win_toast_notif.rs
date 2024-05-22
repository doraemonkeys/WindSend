#![allow(dead_code)]
use std::process::Command;
use std::os::windows::process::CommandExt;
use std::fmt::Write;

pub struct WinToastNotif {
    pub app_id: Option<String>,
    pub duration: Duration,
    pub notif_open: Option<String>,
    pub title: Option<String>,
    pub messages: Option<Vec<String>>,
    pub logo: Option<String>,
    pub logo_circle: CropCircle,
    pub image: Option<String>,
    pub image_placement: ImagePlacement,
    pub actions: Option<Vec<Action>>,
    pub audio: Option<Audio>,
    pub audio_loop: Loop,
}

impl WinToastNotif {
    pub fn new() -> Self {
        Self {
            app_id: None,
            notif_open: None,
            duration: Duration::Short,
            title: None,
            messages: Some(vec![String::from("Hellow World")]),
            logo: None,
            logo_circle: CropCircle::False,
            image: None,
            image_placement: ImagePlacement::Top,
            actions: None,
            audio: None,
            audio_loop: Loop::False,
        }
    }
  
    pub fn set_app_id(mut self, id: &str) -> Self {
        self.app_id = Some(id.into());
        self
    }

    pub fn set_duration(mut self, duration: Duration) -> Self {
        self.duration = duration;
        self
    }
    
    pub fn set_notif_open(mut self, url: &str) -> Self {
        self.notif_open = Some(url.trim().into());
        self
    }

    pub fn set_title(mut self, title: &str) -> Self {
        self.title = Some(title.into());
        self
    }

    pub fn set_messages(mut self, messages: Vec<&str>) -> Self {
        self.messages = Some(Box::new(messages.iter().map(|t| t.to_string())).collect());
        self
    }

    pub fn set_logo(mut self, path: &str, hint_crop: CropCircle) -> Self {
        self.logo = Some(path.trim().into());
        self.logo_circle = hint_crop;
        self
    }

    pub fn set_image(mut self, path: &str, position: ImagePlacement) -> Self {
        self.image = Some(path.trim().into());
        self.image_placement = position;
        self
    }

    pub fn set_actions(mut self, actions: Vec<Action>) -> Self {
        self.actions = Some(actions);
        self
    }

    pub fn set_audio(mut self, audio: Audio, audio_loop: Loop) -> Self {
        self.audio = Some(audio);
        self.audio_loop = audio_loop;
        self
    }

    pub fn show(&self) {
        // Create a String instance and preallocate 2000 bytes of memory for it, reduce the number of memory reallocations
        let mut command = String::with_capacity(2000);
        // Start of XML
        command.push_str("$xml = @\"");
        write!(command, r#"
            <toast{}{}>
                <visual>
                    <binding template="ToastGeneric">
                        {}
                        {}
                        {}
                        {}
                    </binding>
                </visual>
                <actions>
                    {}
                </actions>
                {}
            </toast>
            "#,
            match &self.notif_open {
                Some(url) => format!(r#" activationType="protocol" launch="{}""#, url),
                None => String::new()
            },
            match &self.duration {
                Duration::Short => "",
                Duration::Long => r#" duration="long""#,
                Duration::TimeOut => r#"scenario="incomingCall""#
            },
            match (&self.logo, &self.logo_circle) {
                (Some(logo), CropCircle::True) => format!("\n<image placement=\"appLogoOverride\" hint-crop=\"circle\" src=\"{}\"/>", &logo),
                (Some(logo), CropCircle::False) => format!("\n<image placement=\"appLogoOverride\" src=\"{}\"/>", &logo),
                (None, _) => String::new()
            },
            match &self.title {
                Some(title) => format!("\n<text>{}</text>", &title),
                None => String::new()
            },
            match &self.messages {
                Some(messages) => messages
                    .iter()
                    .map(|message| format!("\n<text>{}</text>", message))
                    .collect::<String>(),
                None => String::new()
            },
            match (&self.image, &self.image_placement){
                (Some(image), ImagePlacement::Top) => format!("\n<image placement=\"hero\" src=\"{}\"/>", &image),
                (Some(image), ImagePlacement::Bottom) => format!("\n<image src=\"{}\"/>", &image),
                (None, _) => String::new()
            },
            match &self.actions {
                Some(actions) => actions
                    .iter()
                    .map(|action| {
                        format!("\n<action content=\"{}\" activationType=\"{}\" arguments=\"{}\" />",
                        action.action_content,
                        action.activation_type.as_str(),
                        action.arguments
                        )
                    })
                    .collect::<String>(),
                None => String::new()
            },
            match &self.audio {
                Some(audio) => match (audio, &self.audio_loop) {
                        (Audio::From(_), _) => String::from("\n<audio silent=\"true\" />"),
                        (_, Loop::False) => format!("\n<audio src=\"{}\" />", audio.as_str()),
                        (_, Loop::True) => format!("\n<audio src=\"{}\" loop=\"true\" />", audio.as_str())
                },
                None => String::from("\n<audio silent=\"true\" />")
            }
        ).unwrap();
        // End of XML: 终止符("@)前面不能有空格
        command.push_str("\n\"@");
        // Powershell: AppId
        write!(command, r#"
            $XmlDocument = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]::New()
            $XmlDocument.loadXml($xml)
            $AppId = '{}'
            [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]::CreateToastNotifier($AppId).Show($XmlDocument)
            "#,
            match &self.app_id {
                Some(id) => id,
                None => r"{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe"
            }
        ).unwrap();
        // Audio Source
        match &self.audio {
            Some(Audio::From(path_or_url)) => write!(command,
                r#"
                $MediaPlayer = [Windows.Media.Playback.MediaPlayer, Windows.Media, ContentType = WindowsRuntime]::New()
                $MediaPlayer.Source = [Windows.Media.Core.MediaSource]::CreateFromUri('{}')
                $MediaPlayer.Play()
                "#, path_or_url
            ).unwrap(),
            _ => println!("audio is not from source")
        }
        // Run it by PowerShell
        Command::new("powershell")
            .creation_flags(0x08000000)
            .args(&["-Command", &command])
            .output()
            .expect("Failed to execute command");
    }
}

// 通知持续时间
pub enum Duration {
    Short,
    Long,
    TimeOut,
}

pub struct Action {
    pub activation_type: ActivationType,
    pub action_content: &'static str,
    pub arguments: &'static str,
}

pub enum ActivationType {
    Protocol,     // 使用协议激活功能启动不同的应用程序
    System,
    Background,   // 触发相应的后台任务，而不会中断用户
    Foreground,   // 启动前台应用程序（默认值）
}

impl ActivationType {
    pub fn as_str(&self) -> &'static str {
        match self {
            ActivationType::Foreground => "foreground",
            ActivationType::Background => "background",
            ActivationType::Protocol => "protocol",
            ActivationType::System => "system",
        }
    }
}

// 圆形Logo
pub enum CropCircle {
    True,
    False
}

// 图片位置
pub enum ImagePlacement {
    Top,
    Bottom
}

// 音频
pub enum Audio {
    From(&'static str),
    WinDefault,
    WinIM,
    WinMail,
    WinRemainder,
    WinSMS,
    WinLoopingAlarm1,
    WinLoopingAlarm2,
    WinLoopingAlarm3,
    WinLoopingAlarm4,
    WinLoopingAlarm5,
    WinLoopingAlarm6,
    WinLoopingAlarm7,
    WinLoopingAlarm8,
    WinLoopingAlarm9,
    WinLoopingAlarm10,
    WinLoopingCall1,
    WinLoopingCall2,
    WinLoopingCall3,
    WinLoopingCall4,
    WinLoopingCall5,
    WinLoopingCall6,
    WinLoopingCall7,
    WinLoopingCall8,
    WinLoopingCall9,
    WinLoopingCall10,
}

impl Audio {
    pub fn as_str(&self) -> &'static str {
        match self {
            Audio::From(path_or_url) => path_or_url,
            Audio::WinDefault => "ms-winsoundevent:Notification.Default",
            Audio::WinIM => "ms-winsoundevent:Notification.IM",
            Audio::WinMail => "ms-winsoundevent:Notification.Mail",
            Audio::WinRemainder => "ms-winsoundevent:Notification.Remainder",
            Audio::WinSMS => "ms-winsoundevent:Notification.SMS",
            Audio::WinLoopingAlarm1 => "ms-winsoundevent:Notification.Looping.Alarm",
            Audio::WinLoopingAlarm2 => "ms-winsoundevent:Notification.Looping.Alarm2",
            Audio::WinLoopingAlarm3 => "ms-winsoundevent:Notification.Looping.Alarm3",
            Audio::WinLoopingAlarm4 => "ms-winsoundevent:Notification.Looping.Alarm4",
            Audio::WinLoopingAlarm5 => "ms-winsoundevent:Notification.Looping.Alarm5",
            Audio::WinLoopingAlarm6 => "ms-winsoundevent:Notification.Looping.Alarm6",
            Audio::WinLoopingAlarm7 => "ms-winsoundevent:Notification.Looping.Alarm7",
            Audio::WinLoopingAlarm8 => "ms-winsoundevent:Notification.Looping.Alarm8",
            Audio::WinLoopingAlarm9 => "ms-winsoundevent:Notification.Looping.Alarm9",
            Audio::WinLoopingAlarm10 => "ms-winsoundevent:Notification.Looping.Alarm10",
            Audio::WinLoopingCall1 => "ms-winsoundevent:Notification.Looping.Call",
            Audio::WinLoopingCall2 => "ms-winsoundevent:Notification.Looping.Call2",
            Audio::WinLoopingCall3 => "ms-winsoundevent:Notification.Looping.Call3",
            Audio::WinLoopingCall4 => "ms-winsoundevent:Notification.Looping.Call4",
            Audio::WinLoopingCall5 => "ms-winsoundevent:Notification.Looping.Call5",
            Audio::WinLoopingCall6 => "ms-winsoundevent:Notification.Looping.Call6",
            Audio::WinLoopingCall7 => "ms-winsoundevent:Notification.Looping.Call7",
            Audio::WinLoopingCall8 => "ms-winsoundevent:Notification.Looping.Call8",
            Audio::WinLoopingCall9 => "ms-winsoundevent:Notification.Looping.Call9",
            Audio::WinLoopingCall10 => "ms-winsoundevent:Notification.Looping.Call10",
        }
    }
}

// 音频循环
pub enum Loop {
    True,
    False
}