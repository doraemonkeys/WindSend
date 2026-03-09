use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::time::SystemTime;
use unicode_normalization::UnicodeNormalization;

#[derive(Debug, thiserror::Error)]
pub enum ClipboardPayloadCodecError {
    #[error("failed to encode or decode text bundle JSON: {0}")]
    Json(#[from] serde_json::Error),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ClipboardPayloadKind {
    TextBundle,
    ImagePng,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ClipboardObservationSource {
    OnDemandRead,
    ClipboardWatcher,
    RecoveryCatchUp,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TextBundle {
    pub plain_text: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub html: Option<String>,
}

impl TextBundle {
    pub fn new(plain_text: impl Into<String>, html: Option<String>) -> Self {
        Self {
            plain_text: plain_text.into(),
            html,
        }
    }

    pub fn from_plain_text(plain_text: impl Into<String>) -> Self {
        Self::new(plain_text, None)
    }

    pub fn normalized_plain_text(&self) -> String {
        normalize_plain_text(&self.plain_text)
    }

    pub fn fingerprint(&self) -> TextFingerprint {
        TextFingerprint {
            plain_text_key: FingerprintKey::from_utf8(&self.normalized_plain_text()),
            html_key: self
                .html
                .as_deref()
                .and_then(normalize_html_fragment)
                .map(|normalized| FingerprintKey::from_utf8(&normalized)),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ImagePng {
    bytes: Vec<u8>,
}

impl ImagePng {
    pub fn new(bytes: Vec<u8>) -> Self {
        Self { bytes }
    }

    pub fn bytes(&self) -> &[u8] {
        &self.bytes
    }

    pub fn fingerprint(&self) -> ImageFingerprint {
        ImageFingerprint {
            image_key: image_fingerprint_key(&self.bytes),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ClipboardPayload {
    Text(TextBundle),
    ImagePng(ImagePng),
}

impl ClipboardPayload {
    pub fn kind(&self) -> ClipboardPayloadKind {
        match self {
            Self::Text(_) => ClipboardPayloadKind::TextBundle,
            Self::ImagePng(_) => ClipboardPayloadKind::ImagePng,
        }
    }

    pub fn encode_body(&self) -> Result<Vec<u8>, ClipboardPayloadCodecError> {
        match self {
            Self::Text(bundle) => Ok(serde_json::to_vec(bundle)?),
            Self::ImagePng(image) => Ok(image.bytes().to_vec()),
        }
    }

    pub fn decode_body(
        payload_kind: ClipboardPayloadKind,
        body: &[u8],
    ) -> Result<Self, ClipboardPayloadCodecError> {
        match payload_kind {
            ClipboardPayloadKind::TextBundle => {
                Ok(Self::Text(serde_json::from_slice::<TextBundle>(body)?))
            }
            ClipboardPayloadKind::ImagePng => Ok(Self::ImagePng(ImagePng::new(body.to_vec()))),
        }
    }

    pub fn fingerprint(&self) -> ClipboardFingerprint {
        match self {
            Self::Text(bundle) => ClipboardFingerprint::Text(bundle.fingerprint()),
            Self::ImagePng(image) => ClipboardFingerprint::Image(image.fingerprint()),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClipboardSnapshot {
    pub payload: ClipboardPayload,
    pub observed_at: SystemTime,
    pub source: ClipboardObservationSource,
}

impl ClipboardSnapshot {
    pub fn new(payload: ClipboardPayload, source: ClipboardObservationSource) -> Self {
        Self {
            payload,
            observed_at: SystemTime::now(),
            source,
        }
    }

    pub fn fingerprint(&self) -> ClipboardFingerprint {
        self.payload.fingerprint()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ClipboardApplyResult {
    Applied,
    AppliedWithDegradation(ClipboardApplyDegradation),
    Failed(ClipboardApplyFailure),
}

impl ClipboardApplyResult {
    pub fn is_success(&self) -> bool {
        !matches!(self, Self::Failed(_))
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClipboardApplyDegradation {
    HtmlDroppedPlainTextOnly,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClipboardApplyFailure {
    pub payload_kind: ClipboardPayloadKind,
    pub message: String,
}

impl ClipboardApplyFailure {
    pub fn new(payload_kind: ClipboardPayloadKind, message: impl Into<String>) -> Self {
        Self {
            payload_kind,
            message: message.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct FingerprintKey(String);

impl FingerprintKey {
    fn from_utf8(value: &str) -> Self {
        Self::from_bytes(value.as_bytes())
    }

    fn from_bytes(value: &[u8]) -> Self {
        let digest = Sha256::digest(value);
        Self(hex::encode(digest))
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ClipboardFingerprint {
    Text(TextFingerprint),
    Image(ImageFingerprint),
}

impl ClipboardFingerprint {
    pub fn semantically_matches(&self, other: &Self) -> bool {
        match (self, other) {
            (Self::Text(left), Self::Text(right)) => left.semantically_matches(right),
            (Self::Image(left), Self::Image(right)) => left == right,
            _ => false,
        }
    }

    pub fn suppression_keys(&self) -> ClipboardSuppressionKeys {
        match self {
            Self::Text(fingerprint) => ClipboardSuppressionKeys::Text {
                plain_text_key: fingerprint.plain_text_key.clone(),
                html_key: fingerprint.html_key.clone(),
            },
            Self::Image(fingerprint) => ClipboardSuppressionKeys::Image {
                image_key: fingerprint.image_key.clone(),
            },
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TextFingerprint {
    pub plain_text_key: FingerprintKey,
    pub html_key: Option<FingerprintKey>,
}

impl TextFingerprint {
    pub fn semantically_matches(&self, other: &Self) -> bool {
        if self.plain_text_key != other.plain_text_key {
            return false;
        }
        match (&self.html_key, &other.html_key) {
            (Some(left), Some(right)) => left == right,
            _ => true,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ImageFingerprint {
    pub image_key: FingerprintKey,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ClipboardSuppressionKeys {
    Text {
        plain_text_key: FingerprintKey,
        html_key: Option<FingerprintKey>,
    },
    Image {
        image_key: FingerprintKey,
    },
}

impl ClipboardSuppressionKeys {
    pub fn matches(&self, observed: &Self) -> bool {
        match (self, observed) {
            (
                Self::Text {
                    plain_text_key: left_plain_text_key,
                    html_key: left_html_key,
                },
                Self::Text {
                    plain_text_key: right_plain_text_key,
                    html_key: right_html_key,
                },
            ) => {
                if left_plain_text_key != right_plain_text_key {
                    return false;
                }

                match (left_html_key, right_html_key) {
                    (Some(left), Some(right)) => left == right,
                    _ => true,
                }
            }
            (Self::Image { image_key: left }, Self::Image { image_key: right }) => left == right,
            _ => false,
        }
    }
}

pub fn normalize_plain_text(value: &str) -> String {
    let without_bom = value.strip_prefix('\u{feff}').unwrap_or(value);
    let normalized_line_endings = without_bom.replace("\r\n", "\n").replace('\r', "\n");
    normalized_line_endings.nfc().collect()
}

pub fn normalize_html_fragment(value: &str) -> Option<String> {
    let _ = value;
    // We intentionally omit htmlKey until both runtimes share an identical HTML5
    // fragment normalizer with golden fixtures; an ad-hoc approximation here would
    // make suppression drift before the protocol boundary is stable.
    None
}

fn image_fingerprint_key(png_bytes: &[u8]) -> FingerprintKey {
    let pixel_bytes = image::load_from_memory(png_bytes).ok().map(|image| {
        let width = image.width().to_le_bytes();
        let height = image.height().to_le_bytes();
        let rgba = image.to_rgba8();
        let mut normalized = Vec::with_capacity(width.len() + height.len() + rgba.as_raw().len());
        normalized.extend_from_slice(&width);
        normalized.extend_from_slice(&height);
        normalized.extend_from_slice(rgba.as_raw());
        normalized
    });

    match pixel_bytes {
        Some(bytes) => FingerprintKey::from_bytes(&bytes),
        None => FingerprintKey::from_bytes(png_bytes),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_plain_text_removes_single_bom_normalizes_newlines_and_nfc() {
        let input = "\u{feff}A\r\nB\rC\u{0065}\u{0301}";
        assert_eq!(normalize_plain_text(input), "A\nB\nCé");
    }

    #[test]
    fn normalize_plain_text_preserves_user_whitespace() {
        let input = "\t  keep  spaces\t";
        assert_eq!(normalize_plain_text(input), input);
    }

    #[test]
    fn text_fingerprint_requires_matching_html_only_when_both_sides_have_html_keys() {
        let plain = FingerprintKey::from_utf8("same");
        let html_a = FingerprintKey::from_utf8("<b>a</b>");
        let html_b = FingerprintKey::from_utf8("<i>b</i>");
        let with_html = TextFingerprint {
            plain_text_key: plain.clone(),
            html_key: Some(html_a),
        };
        let same_plain_no_html = TextFingerprint {
            plain_text_key: plain.clone(),
            html_key: None,
        };
        let different_html = TextFingerprint {
            plain_text_key: plain,
            html_key: Some(html_b),
        };

        assert!(with_html.semantically_matches(&same_plain_no_html));
        assert!(!with_html.semantically_matches(&different_html));
    }

    #[test]
    fn image_fingerprint_falls_back_to_raw_bytes_for_invalid_png() {
        let invalid = ImagePng::new(vec![1, 2, 3, 4]);
        assert_eq!(
            invalid.fingerprint().image_key,
            FingerprintKey::from_bytes(&[1, 2, 3, 4])
        );
    }

    #[test]
    fn html_key_is_omitted_until_shared_normalizer_exists() {
        let bundle = TextBundle::new("hello", Some("<b>hello</b>".to_string()));
        assert!(bundle.fingerprint().html_key.is_none());
    }

    #[test]
    fn suppression_keys_fall_back_to_plain_text_when_html_key_is_missing() {
        let with_html =
            ClipboardPayload::Text(TextBundle::new("hello", Some("<b>hello</b>".to_string())));
        let plain_only = ClipboardPayload::Text(TextBundle::from_plain_text("hello"));

        assert!(
            with_html
                .fingerprint()
                .suppression_keys()
                .matches(&plain_only.fingerprint().suppression_keys())
        );
    }

    #[test]
    fn text_payload_body_round_trips_through_json_codec() {
        let payload =
            ClipboardPayload::Text(TextBundle::new("hello", Some("<b>hello</b>".to_string())));

        let encoded = payload.encode_body().unwrap();
        let decoded =
            ClipboardPayload::decode_body(ClipboardPayloadKind::TextBundle, &encoded).unwrap();

        assert_eq!(decoded, payload);
    }

    #[test]
    fn image_payload_body_round_trips_through_raw_bytes_codec() {
        let payload = ClipboardPayload::ImagePng(ImagePng::new(vec![1, 2, 3, 4]));

        let encoded = payload.encode_body().unwrap();
        let decoded =
            ClipboardPayload::decode_body(ClipboardPayloadKind::ImagePng, &encoded).unwrap();

        assert_eq!(decoded, payload);
    }
}
