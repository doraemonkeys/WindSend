use crate::sync::clipboard_domain::{
    ClipboardApplyDegradation, ClipboardApplyFailure, ClipboardApplyResult,
    ClipboardObservationSource, ClipboardPayload, ClipboardPayloadKind, ClipboardSnapshot,
    ImagePng, TextBundle,
};
use clipboard_rs::{Clipboard, ClipboardContent, ContentFormat, common::RustImage};
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

fn encode_raw_clipboard_image_as_png(
    raw_image: ClipboardImage<'_>,
) -> Result<ImagePng, Box<dyn std::error::Error + Send + Sync>> {
    let dyn_img = if let Some(image1) = raw_image.image1 {
        let img_buf = image::ImageBuffer::from_vec(
            image1.width as u32,
            image1.height as u32,
            image1.bytes.into_owned(),
        )
        .ok_or("image::ImageBuffer::from_vec failed")?;
        image::DynamicImage::ImageRgba8(img_buf)
    } else if let Some(image2) = raw_image.image2 {
        use clipboard_rs::common::RustImage;
        image2
            .get_dynamic_image()
            .map_err(|error| format!("image2.get_dynamic_image failed, err: {error}"))?
    } else {
        return Err("no image in clipboard".into());
    };

    let mut cursor = std::io::Cursor::new(Vec::new());
    dyn_img.write_to(&mut cursor, image::ImageFormat::Png)?;
    Ok(ImagePng::new(cursor.into_inner()))
}

fn text_bundle_from_contents(contents: Vec<ClipboardContent>) -> Option<TextBundle> {
    let mut plain_text = None;
    let mut html = None;

    for content in contents {
        match content {
            ClipboardContent::Text(text) => plain_text = Some(text),
            ClipboardContent::Html(fragment) => html = Some(fragment),
            _ => {}
        }
    }

    plain_text.map(|plain_text| TextBundle::new(plain_text, html))
}

fn clipboard_contents_for_text_bundle(bundle: &TextBundle) -> Vec<ClipboardContent> {
    let mut contents = vec![ClipboardContent::Text(bundle.plain_text.clone())];
    if let Some(html) = &bundle.html {
        contents.push(ClipboardContent::Html(html.clone()));
    }
    contents
}

impl ClipboardManager {
    pub fn new() -> Result<Self, Box<dyn std::error::Error>> {
        Ok(Self {
            instance: std::sync::Mutex::new(ClipboardInstance::new()?),
        })
    }

    pub fn read_text_bundle(&self) -> Result<TextBundle, Box<dyn std::error::Error + Send + Sync>> {
        let mut instance = self.instance.lock().unwrap();

        if let Some(ref context) = instance.context
            && let Ok(contents) = context.get(&[ContentFormat::Text, ContentFormat::Html])
            && let Some(bundle) = text_bundle_from_contents(contents)
        {
            return Ok(bundle);
        }

        #[cfg(not(target_os = "linux"))]
        if let Some(ref mut arboard) = instance.arboard {
            Ok(TextBundle::from_plain_text(arboard.get_text()?))
        } else {
            Err("Clipboard not initialized".into())
        }

        #[cfg(target_os = "linux")]
        if let Some(ref mut arboard) = instance.arboard {
            Ok(TextBundle::from_plain_text(arboard.get_text()?))
        } else {
            Err("Clipboard not initialized".into())
        }
    }

    pub fn read_text_snapshot(
        &self,
        source: ClipboardObservationSource,
    ) -> Result<ClipboardSnapshot, Box<dyn std::error::Error + Send + Sync>> {
        Ok(ClipboardSnapshot::new(
            ClipboardPayload::Text(self.read_text_bundle()?),
            source,
        ))
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

    pub fn read_image_png(&self) -> Result<ImagePng, Box<dyn std::error::Error + Send + Sync>> {
        encode_raw_clipboard_image_as_png(self.read_image()?)
    }

    pub fn read_image_snapshot(
        &self,
        source: ClipboardObservationSource,
    ) -> Result<ClipboardSnapshot, Box<dyn std::error::Error + Send + Sync>> {
        Ok(ClipboardSnapshot::new(
            ClipboardPayload::ImagePng(self.read_image_png()?),
            source,
        ))
    }

    pub fn read_supported_snapshot(
        &self,
        source: ClipboardObservationSource,
    ) -> Result<ClipboardSnapshot, Box<dyn std::error::Error + Send + Sync>> {
        match self.read_image_snapshot(source) {
            Ok(snapshot) => Ok(snapshot),
            Err(image_error) => match self.read_text_snapshot(source) {
                Ok(snapshot) => Ok(snapshot),
                Err(text_error) => Err(format!(
                    "no supported clipboard payload available, image error: {image_error}, text error: {text_error}"
                )
                .into()),
            },
        }
    }

    pub fn read_image(
        &self,
    ) -> Result<ClipboardImage<'_>, Box<dyn std::error::Error + Send + Sync>> {
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
                .map(|f| match urlencoding::decode(&f) {
                    Ok(decoded) => decoded.into_owned(),
                    Err(e) => {
                        tracing::error!("urlencoding::decode failed, err: {}", e);
                        f
                    }
                })
                .filter(|f| !f.is_empty())
                .collect::<Vec<_>>();
            return Ok(files);
        }
        Err("Clipboard context not initialized".into())
    }

    pub fn apply_payload(&self, payload: &ClipboardPayload) -> ClipboardApplyResult {
        match payload {
            ClipboardPayload::Text(bundle) => self.apply_text_bundle(bundle),
            ClipboardPayload::ImagePng(image) => self.apply_image_png(image),
        }
    }

    pub fn apply_text_bundle(&self, bundle: &TextBundle) -> ClipboardApplyResult {
        let mut instance = self.instance.lock().unwrap();

        if let Some(ref mut context) = instance.context {
            let contents = clipboard_contents_for_text_bundle(bundle);
            match context.set(contents) {
                Ok(()) => return ClipboardApplyResult::Applied,
                Err(error) => {
                    debug!(?error, "rich text apply fell back to plain text");
                }
            }
        }

        match write_plain_text_via_available_backend(&mut instance, bundle.plain_text.as_str()) {
            Ok(()) if bundle.html.is_some() => ClipboardApplyResult::AppliedWithDegradation(
                ClipboardApplyDegradation::HtmlDroppedPlainTextOnly,
            ),
            Ok(()) => ClipboardApplyResult::Applied,
            Err(error) => ClipboardApplyResult::Failed(ClipboardApplyFailure::new(
                ClipboardPayloadKind::TextBundle,
                error.to_string(),
            )),
        }
    }

    pub fn apply_image_png(&self, image: &ImagePng) -> ClipboardApplyResult {
        match self.write_image_from_bytes(image.bytes()) {
            Ok(()) => ClipboardApplyResult::Applied,
            Err(error) => ClipboardApplyResult::Failed(ClipboardApplyFailure::new(
                ClipboardPayloadKind::ImagePng,
                error.to_string(),
            )),
        }
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

fn write_plain_text_via_available_backend(
    instance: &mut ClipboardInstance,
    text: &str,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    #[cfg(not(target_os = "linux"))]
    if let Some(ref mut context) = instance.context {
        context.set_text(text.to_string())
    } else if let Some(ref mut arboard) = instance.arboard {
        Ok(arboard.set_text(text)?)
    } else {
        Err("Clipboard not initialized".into())
    }

    #[cfg(target_os = "linux")]
    if let Some(ref mut arboard) = instance.arboard {
        Ok(arboard.set_text(text)?)
    } else if let Some(ref mut context) = instance.context {
        context.set_text(text.to_string())
    } else {
        Err("Clipboard not initialized".into())
    }
}

#[cfg(test)]
mod tests {
    use clipboard_rs::ClipboardContent;

    use super::{clipboard_contents_for_text_bundle, text_bundle_from_contents};
    use crate::sync::clipboard_domain::TextBundle;

    #[test]
    fn clipboard_contents_round_trip_text_bundle_with_html() {
        let bundle = TextBundle::new("hello", Some("<b>hello</b>".to_string()));
        let contents = clipboard_contents_for_text_bundle(&bundle);

        assert!(matches!(&contents[0], ClipboardContent::Text(text) if text == "hello"));
        assert!(matches!(&contents[1], ClipboardContent::Html(html) if html == "<b>hello</b>"));
        assert_eq!(text_bundle_from_contents(contents), Some(bundle));
    }

    #[test]
    fn text_bundle_from_contents_ignores_non_text_variants() {
        let bundle = text_bundle_from_contents(vec![
            ClipboardContent::Html("<i>hello</i>".to_string()),
            ClipboardContent::Text("hello".to_string()),
            ClipboardContent::Rtf("{\\rtf1 hello}".to_string()),
        ]);

        assert_eq!(
            bundle,
            Some(TextBundle::new("hello", Some("<i>hello</i>".to_string())))
        );
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn test_urlencoding() {
        let url = "file://test.txt中文";
        let decoded = urlencoding::decode(&url).unwrap();
        assert_eq!(decoded.into_owned(), "file://test.txt中文");
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn test_urlencoding_decode_failed() {
        let url = "file://test.txt%E4%B8%AD%E6%96%87";
        let decoded = urlencoding::decode(&url).unwrap();
        assert_eq!(decoded.into_owned(), "file://test.txt中文");
    }
}
