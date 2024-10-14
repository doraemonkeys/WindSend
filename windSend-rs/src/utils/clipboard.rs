use clipboard_rs::{common::RustImage, Clipboard};
use tracing::debug;

pub struct ClipboardManager {
    /// Used to ensure that only one thread attempts to access the clipboard at a time
    instance: std::sync::Mutex<ClipboardInstance>,
}

struct ClipboardInstance {
    /// only use arboard on linux wayland
    arboard: Option<arboard::Clipboard>,
    /// not support linux wayland
    context: Option<clipboard_rs::ClipboardContext>,
}

impl ClipboardInstance {
    fn new() -> Result<Self, Box<dyn std::error::Error>> {
        // keep atleast one reference to arboard clipboard to prevent it from being dropped
        let arboard_instance = arboard::Clipboard::new();
        let context_instance = clipboard_rs::ClipboardContext::new();
        if arboard_instance.is_err() && context_instance.is_err() {
            return Err(format!(
                "Failed to initialize clipboard: arboard error:{:?},clipboard_rs error:{:?}",
                arboard_instance.err(),
                context_instance.err()
            )
            .into());
        }
        Ok(Self {
            arboard: arboard_instance.ok(),
            context: context_instance.ok(),
        })
    }
}

use arboard::ImageData;
use clipboard_rs::RustImageData;
pub struct ClipboardImage<'a> {
    pub image1: Option<ImageData<'a>>,
    pub image2: Option<RustImageData>,
}

impl ClipboardManager {
    pub fn new() -> Result<Self, Box<dyn std::error::Error>> {
        Ok(Self {
            instance: std::sync::Mutex::new(ClipboardInstance::new()?),
        })
    }

    pub fn read_text(&self) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
        let mut instance = self.instance.lock().unwrap();
        #[cfg(not(target_os = "linux"))]
        if let Some(ref context) = instance.context {
            context.get_text()
        } else if let Some(ref mut arboard) = instance.arboard {
            Ok(arboard.get_text()?)
        } else {
            Err("Clipboard not initialized".into())
        }
        #[cfg(target_os = "linux")]
        if let Some(ref mut arboard) = instance.arboard {
            Ok(arboard.get_text()?)
        } else if let Some(ref mut context) = instance.context {
            context.get_text()
        } else {
            Err("Clipboard not initialized".into())
        }
    }
    pub fn write_text<'a, T: Into<std::borrow::Cow<'a, str>>>(
        &self,
        text: T,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let mut instance = self.instance.lock().unwrap();
        #[cfg(not(target_os = "linux"))]
        if let Some(ref mut context) = instance.context {
            context.set_text(String::from(text.into()))
        } else if let Some(ref mut arboard) = instance.arboard {
            Ok(arboard.set_text(text)?)
        } else {
            Err("Clipboard not initialized".into())
        }
        #[cfg(target_os = "linux")]
        if let Some(ref mut arboard) = instance.arboard {
            Ok(arboard.set_text(text)?)
        } else if let Some(ref mut context) = instance.context {
            context.set_text(String::from(text.into()))
        } else {
            Err("Clipboard not initialized".into())
        }
    }

    pub fn read_image(&self) -> Result<ClipboardImage, Box<dyn std::error::Error + Send + Sync>> {
        let mut ret = ClipboardImage {
            image1: None,
            image2: None,
        };
        let mut instance = self.instance.lock().unwrap();
        if let Some(ref mut arboard) = instance.arboard {
            ret.image1 = Some(arboard.get_image()?);
        } else if let Some(ref context) = instance.context {
            ret.image2 = Some(context.get_image()?);
        } else {
            return Err("Clipboard not initialized".into());
        }
        Ok(ret)
    }

    pub fn write_image(
        &self,
        image: image::DynamicImage,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let mut instance = self.instance.lock().unwrap();
        if let Some(ref mut arboard) = instance.arboard {
            // In order of priority CF_DIB and CF_BITMAP
            let img_data = arboard::ImageData {
                width: image.width() as usize,
                height: image.height() as usize,
                bytes: std::borrow::Cow::from(image.into_bytes()),
            };
            let now = std::time::SystemTime::now();
            arboard.set_image(img_data)?;
            debug!("write_image: {:?}", now.elapsed());
            Ok(())
        } else if let Some(ref mut context) = instance.context {
            let img_data = clipboard_rs::common::RustImageData::from_dynamic_image(image);
            Ok(context.set_image(img_data)?)
        } else {
            Err("Clipboard not initialized".into())
        }
    }

    pub fn write_image_from_bytes(
        &self,
        bytes: &[u8],
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        self.write_image(image::DynamicImage::ImageRgba8(
            image::load_from_memory(bytes)?.to_rgba8(),
        ))
    }

    pub fn get_files(&self) -> Result<Vec<String>, Box<dyn std::error::Error + Send + Sync>> {
        let mut instance = self.instance.lock().unwrap();
        if let Some(ref mut context) = instance.context {
            let files = context.get_files()?;
            debug!("clipboard_rs get_files: {:?}", &files);
            let files = files
                .into_iter()
                .map(|f| f.trim_start_matches("file://").to_string())
                .collect::<Vec<_>>();
            #[cfg(target_os = "linux")]
            let files = files
                .into_iter()
                .map(|f| {
                    urlencoding::decode(&f)
                        .map_err(|e| {
                            error!("urlencoding::decode failed, err: {}", e);
                            e
                        })
                        .unwrap_or_default()
                        .into_owned()
                })
                .filter(|f| !f.is_empty())
                .collect::<Vec<_>>();
            return Ok(files);
        }
        Err("Clipboard context not initialized".into())
    }

    pub fn clear(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let mut instance = self.instance.lock().unwrap();
        if let Some(ref mut arboard) = instance.arboard {
            Ok(arboard.clear()?)
        } else if let Some(ref mut context) = instance.context {
            context.clear()
        } else {
            Err("Clipboard not initialized".into())
        }
    }
}
