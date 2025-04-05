use aes::cipher::{BlockDecryptMut, BlockEncryptMut, KeyIvInit, block_padding::Pkcs7};
// use anyhow::Ok;

// use rand::CryptoRng;
// use rand::Rng;
use rand::RngCore;
use sha2::Digest;

pub fn rand_n_bytes(rng: &mut rand::rngs::ThreadRng, n: usize) -> Vec<u8> {
    let mut bytes = vec![0u8; n];
    rng.fill_bytes(&mut bytes);
    bytes
}

// rand v0.9
// pub fn rand_n_bytes2(n: usize) -> Vec<u8> {
//     use rand::rng;
//     let mut bytes = vec![0u8; n];
//     rng().fill_bytes(&mut bytes);
//     bytes
// }

// rand v0.9
// pub fn generate_rand_bytes_hex(byte_len: usize) -> String {
//     use rand::rng;
//     let mut rng = rng();
//     let bytes = rand_n_bytes(&mut rng, byte_len);
//     hex::encode(bytes)
// }

pub fn rand_n_bytes2(n: usize) -> Vec<u8> {
    use rand::thread_rng;
    let mut bytes = vec![0u8; n];
    thread_rng().fill_bytes(&mut bytes);
    bytes
}

pub fn generate_rand_bytes_hex(byte_len: usize) -> String {
    use rand::thread_rng;
    let mut rng = thread_rng();
    let bytes = rand_n_bytes(&mut rng, byte_len);
    hex::encode(bytes)
}

#[allow(dead_code)]
pub fn compute_sha256(bytes: &[u8]) -> [u8; 32] {
    let mut hasher = sha2::Sha256::new();
    hasher.update(bytes);
    hasher.finalize().into()
}

pub trait SymCryptor {
    fn encrypt(&self, data: &[u8], iv: &[u8], extra_space: usize) -> anyhow::Result<Vec<u8>>;
    fn decrypt(&self, data: &[u8], iv: &[u8], extra_space: usize) -> anyhow::Result<Vec<u8>>;
}
pub struct AESCbcCrypt {
    key: Vec<u8>,
}

type Aes128CbcEnc = cbc::Encryptor<aes::Aes128>;
type Aes128CbcDec = cbc::Decryptor<aes::Aes128>;
type Aes192CbcEnc = cbc::Encryptor<aes::Aes192>;
type Aes192CbcDec = cbc::Decryptor<aes::Aes192>;
type Aes256CbcEnc = cbc::Encryptor<aes::Aes256>;
type Aes256CbcDec = cbc::Decryptor<aes::Aes256>;

impl AESCbcCrypt {
    const BLOCK_SIZE: usize = 16;
    pub fn new(key: &[u8]) -> anyhow::Result<Self> {
        if key.len() != 16 && key.len() != 24 && key.len() != 32 {
            return Err(anyhow::anyhow!("secretKey length must be 16, 24 or 32"));
        }
        Ok(Self { key: key.to_vec() })
    }
    fn encrypt(
        &self,
        encryptor: impl BlockEncryptMut,
        plain_text: &[u8],
        extra_space: usize,
    ) -> anyhow::Result<Vec<u8>> {
        let mut buf = vec![0u8; plain_text.len() + AESCbcCrypt::BLOCK_SIZE + extra_space];
        let cipher_text = encryptor.encrypt_padded_b2b_mut::<Pkcs7>(plain_text, &mut buf);
        match cipher_text {
            Ok(text) => {
                let len = text.len();
                buf.truncate(len);
                Ok(buf)
            }
            Err(e) => Err(anyhow::anyhow!(e)),
        }
    }
    fn decrypt(
        &self,
        decryptor: impl BlockDecryptMut,
        data: &[u8],
        extra_space: usize,
    ) -> anyhow::Result<Vec<u8>> {
        let mut buf = vec![0u8; data.len() + AESCbcCrypt::BLOCK_SIZE + extra_space];
        let plain_text = decryptor.decrypt_padded_b2b_mut::<Pkcs7>(data, &mut buf);
        if let Err(e) = plain_text {
            return Err(anyhow::anyhow!(e));
        }
        let len = plain_text.unwrap().len();
        buf.truncate(len);
        Ok(buf)
    }
}

impl SymCryptor for AESCbcCrypt {
    fn encrypt(&self, plain_text: &[u8], iv: &[u8], extra_space: usize) -> anyhow::Result<Vec<u8>> {
        match self.key.len() {
            16 => {
                let key = &self.key[..16];
                let encryptor = Aes128CbcEnc::new(key.into(), iv.into());
                self.encrypt(encryptor, plain_text, extra_space)
            }
            24 => {
                let key = &self.key[..24];
                let encryptor = Aes192CbcEnc::new(key.into(), iv.into());
                self.encrypt(encryptor, plain_text, extra_space)
            }
            32 => {
                let key = &self.key[..32];
                let encryptor = Aes256CbcEnc::new(key.into(), iv.into());
                self.encrypt(encryptor, plain_text, extra_space)
            }
            _ => Err(anyhow::anyhow!("unsupported key length")),
        }
    }

    fn decrypt(&self, data: &[u8], iv: &[u8], extra_space: usize) -> anyhow::Result<Vec<u8>> {
        match self.key.len() {
            16 => {
                let key = &self.key[..16];
                let decryptor = Aes128CbcDec::new(key.into(), iv.into());
                self.decrypt(decryptor, data, extra_space)
            }
            24 => {
                let key = &self.key[..24];
                let decryptor = Aes192CbcDec::new(key.into(), iv.into());
                self.decrypt(decryptor, data, extra_space)
            }
            32 => {
                let key = &self.key[..32];
                let decryptor = Aes256CbcDec::new(key.into(), iv.into());
                self.decrypt(decryptor, data, extra_space)
            }
            _ => Err(anyhow::anyhow!("unsupported key length")),
        }
    }
}

pub struct AESCbcFollowedCrypt {
    cryptor: AESCbcCrypt,
}

impl AESCbcFollowedCrypt {
    pub fn new(key: &[u8]) -> anyhow::Result<Self> {
        let cryptor = AESCbcCrypt::new(key)?;
        Ok(Self { cryptor })
    }
    pub fn encrypt(&self, plain_text: &[u8]) -> anyhow::Result<Vec<u8>> {
        let iv = rand_n_bytes2(AESCbcCrypt::BLOCK_SIZE);
        let mut cipher_text = SymCryptor::encrypt(&self.cryptor, plain_text, &iv, iv.len())?;
        cipher_text.extend_from_slice(&iv);
        Ok(cipher_text)
    }
    pub fn decrypt(&self, data: &[u8]) -> anyhow::Result<Vec<u8>> {
        if data.len() <= AESCbcCrypt::BLOCK_SIZE {
            return Err(anyhow::anyhow!(
                "data length must be greater than {}",
                AESCbcCrypt::BLOCK_SIZE
            ));
        }
        let iv = &data[data.len() - AESCbcCrypt::BLOCK_SIZE..];
        let data = &data[..data.len() - AESCbcCrypt::BLOCK_SIZE];
        SymCryptor::decrypt(&self.cryptor, data, iv, 0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn test_aes_cbc() {
        let key = "1234567890123456".as_bytes();
        let cryptor = AESCbcCrypt::new(key).unwrap();
        let plain_text = "hello world".as_bytes();
        let iv = "1234567890123456".as_bytes();
        // let cipher_text = cryptor.encrypt(plain_text, iv, 0).unwrap();
        let cipher_text = SymCryptor::encrypt(&cryptor, plain_text, iv, 0).unwrap();
        let plain_text2 = SymCryptor::decrypt(&cryptor, &cipher_text, iv, 0).unwrap();
        assert_eq!(plain_text, plain_text2.as_slice());
    }
    #[test]
    fn test_aes_cbc_followed() {
        let key = "1234567890123456".as_bytes();
        let cryptor = AESCbcFollowedCrypt::new(key).unwrap();
        let plain_text = "hello world".as_bytes();
        let cipher_text = cryptor.encrypt(plain_text).unwrap();
        let plain_text2 = cryptor.decrypt(&cipher_text).unwrap();
        assert_eq!(plain_text, plain_text2.as_slice());
    }
}

use aes_gcm::{
    Aes128Gcm,
    Aes256Gcm,
    Key,
    Nonce, // Import specific types and Nonce
    aead::{AeadCore, AeadInPlace, KeyInit, consts::U12},
};

type Aes192Gcm = aes_gcm::AesGcm<aes_gcm::aes::Aes192, aes_gcm::aead::generic_array::typenum::U12>;

use std::fmt::Debug;
use thiserror::Error; // Ensure Debug is imported if not already

#[derive(Error, Debug)]
pub enum AesGcmError {
    #[error("Invalid key length, requires {0} bytes")]
    InvalidKeyLength(usize),

    #[error("Invalid key: {0}")]
    InvalidKey(String),

    #[error("Invalid Nonce length, requires {0} bytes")]
    #[allow(dead_code)]
    InvalidNonceLength(usize),

    #[error("Encryption failed: {0}")]
    EncryptionFailed(String),

    // Note: In AES-GCM, decryption failure often means the authentication tag didn't match,
    // which can be caused by an incorrect key, incorrect nonce/IV, or tampered ciphertext.
    // This message reflects that common scenario.
    #[error(
        "Decryption failed (authentication tag mismatch: possibly incorrect key, nonce, or tampered ciphertext)"
    )]
    #[allow(dead_code)]
    DecryptionError,

    #[error("Decryption failed: {0}")]
    DecryptionFailed(String),

    #[error("Ciphertext too short")]
    CiphertextTooShort,
}
/// Encapsulates AES-GCM encryption and decryption logic.
/// Supports AES-128, AES-192, and AES-256 based on the provided key length.
/// Handles nonce generation and ciphertext formatting (nonce || ciphertext || tag).
pub struct AesGcmCipher {
    /// The secret key used for encryption and decryption. Its length determines the AES variant.
    key: Vec<u8>,
}

#[allow(dead_code)]
impl AesGcmCipher {
    /// Standard nonce size for AES-GCM (96 bits). Recommended by NIST SP 800-38D.
    pub const NONCE_SIZE: usize = 12;
    /// Standard authentication tag size for AES-GCM (128 bits). Provides strong integrity protection.
    pub const TAG_SIZE: usize = 16;

    /// Creates a new `AesGcmCipher` instance with the given key.
    ///
    /// # Arguments
    ///
    /// * `key` - A byte slice representing the AES key. Must be 16, 24, or 32 bytes long.
    ///
    /// # Errors
    ///
    /// Returns `AesGcmError::InvalidKeyLength` if the key length is not 16, 24, or 32.
    pub fn new(key: &[u8]) -> Result<Self, AesGcmError> {
        if key.len() != 16 && key.len() != 24 && key.len() != 32 {
            return Err(AesGcmError::InvalidKeyLength(key.len()));
        }
        Ok(Self { key: key.to_vec() })
    }

    /// Creates a new `AesGcmCipher` instance from a hexadecimal encoded key string.
    ///
    /// # Arguments
    ///
    /// * `hex` - A string containing the hexadecimal representation of the key.
    ///
    /// # Errors
    ///
    /// Returns `AesGcmError::InvalidKey` if the hex string is malformed.
    /// Returns `AesGcmError::InvalidKeyLength` if the decoded key length is invalid.
    pub fn new_from_hex(hex: &str) -> Result<Self, AesGcmError> {
        let key = hex::decode(hex).map_err(|_| AesGcmError::InvalidKey(hex.to_string()))?;
        Self::new(&key)
    }

    /// Internal helper function to perform encryption using a specific AEAD cipher instance.
    /// This abstracts the core encryption logic, making it reusable for different AES key sizes.
    /// The output format is `nonce || ciphertext || tag`.
    fn encrypt_inner<A: AeadInPlace>(
        &self,
        cipher: A,
        plaintext: &[u8],
        aad: &[u8],
    ) -> Result<Vec<u8>, AesGcmError> {
        let nonce = self.generate_nonce();
        let nonce = aes_gcm::aead::Nonce::<A>::from_slice(nonce.as_slice());
        // let nonce = aes_gcm::aead::Nonce::<A>::from_slice(b"123456789012");
        let mut buffer = Vec::with_capacity(plaintext.len() + nonce.len() + Self::TAG_SIZE);
        buffer.extend_from_slice(nonce.as_slice());
        buffer.extend_from_slice(plaintext);
        let tag = cipher
            .encrypt_in_place_detached(nonce, aad, &mut buffer[nonce.len()..])
            .map_err(|e| AesGcmError::EncryptionFailed(e.to_string()))?;
        buffer.extend_from_slice(tag.as_slice());
        Ok(buffer)
    }

    /// Encrypts the given plaintext and associated authenticated data (AAD).
    ///
    /// Selects the appropriate AES variant (128, 192, or 256) based on the key length
    /// provided during initialization. The AAD is authenticated but not encrypted.
    /// Generates a unique nonce for each call.
    ///
    /// # Arguments
    ///
    /// * `plaintext` - The data to encrypt.
    /// * `aad` - Additional Associated Data to authenticate. Can be empty.
    ///
    /// # Returns
    ///
    /// A `Vec<u8>` containing `nonce || ciphertext || tag` on success.
    ///
    /// # Errors
    ///
    /// Returns `AesGcmError::EncryptionFailed` if the encryption process fails internally.
    pub fn encrypt(&self, plaintext: &[u8], aad: &[u8]) -> Result<Vec<u8>, AesGcmError> {
        match self.key.len() {
            16 => self.encrypt_inner(
                Aes128Gcm::new(Key::<Aes128Gcm>::from_slice(&self.key)),
                plaintext,
                aad,
            ),
            24 => self.encrypt_inner(
                Aes192Gcm::new(Key::<Aes192Gcm>::from_slice(&self.key)),
                plaintext,
                aad,
            ),
            32 => self.encrypt_inner(
                Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(&self.key)),
                plaintext,
                aad,
            ),
            _ => unreachable!(),
        }
    }

    /// Internal helper function to perform decryption using a specific AEAD cipher instance.
    /// This abstracts the core decryption and authentication logic. Decryption is performed in-place
    /// on the provided buffer slice.
    /// The expected input format in the buffer is `nonce || ciphertext || tag`.
    fn decrypt_inner<'a, A: AeadInPlace>(
        &self,
        cipher: A,
        ciphertext: &'a mut [u8],
        aad: &[u8],
    ) -> Result<&'a mut [u8], AesGcmError> {
        if ciphertext.len() < Self::NONCE_SIZE + Self::TAG_SIZE {
            return Err(AesGcmError::CiphertextTooShort);
        }
        let (nonce, ciphertext) = ciphertext.split_at_mut(Self::NONCE_SIZE);
        let (ciphertext, tag) = ciphertext.split_at_mut(ciphertext.len() - Self::TAG_SIZE);
        // let tag = aes_gcm::Tag::<U16>::from_slice(tag);
        let tag = aes_gcm::aead::Tag::<A>::from_slice(tag);
        let nonce = aes_gcm::aead::Nonce::<A>::from_slice(nonce);
        cipher
            .decrypt_in_place_detached(nonce, aad, ciphertext, tag)
            .map_err(|e| AesGcmError::DecryptionFailed(e.to_string()))?;
        Ok(ciphertext)
    }

    /// Decrypts the given ciphertext structure (`nonce || encrypted_data || tag`) and verifies associated data (AAD).
    ///
    /// Selects the appropriate AES variant (128, 192, or 256) based on the key length.
    /// Decryption happens *in-place* within the provided `ciphertext` buffer.
    /// On success, the part of the buffer that held the ciphertext will now contain the original plaintext.
    ///
    /// # Arguments
    ///
    /// * `ciphertext` - A mutable byte slice containing the `nonce || ciphertext || tag`.
    ///                  This buffer will be modified: the ciphertext portion is overwritten with plaintext on success.
    /// * `aad` - Additional Associated Data that was used during encryption. Must match exactly.
    ///
    /// # Returns
    ///
    /// A mutable slice `&'a mut [u8]` pointing to the decrypted plaintext within the original `ciphertext` buffer on success.
    /// The lifetime `'a` is tied to the input `ciphertext` buffer.
    ///
    /// # Errors
    ///
    /// * `AesGcmError::CiphertextTooShort` if the input buffer isn't long enough for nonce and tag.
    /// * `AesGcmError::DecryptionFailed` if decryption or authentication fails (e.g., invalid tag, wrong key, tampered data).
    ///   Note: It's intentionally difficult to distinguish specific causes of decryption failure for security reasons.
    pub fn decrypt<'a>(
        &self,
        ciphertext: &'a mut [u8],
        aad: &[u8],
    ) -> Result<&'a mut [u8], AesGcmError> {
        match self.key.len() {
            16 => self.decrypt_inner(
                Aes128Gcm::new(Key::<Aes128Gcm>::from_slice(&self.key)),
                ciphertext,
                aad,
            ),
            24 => self.decrypt_inner(
                Aes192Gcm::new(Key::<Aes192Gcm>::from_slice(&self.key)),
                ciphertext,
                aad,
            ),
            32 => self.decrypt_inner(
                Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(&self.key)),
                ciphertext,
                aad,
            ),
            _ => unreachable!(),
        }
    }

    pub fn generate_nonce(&self) -> Nonce<U12> {
        use aes_gcm::aead::OsRng;
        Aes128Gcm::generate_nonce(&mut OsRng)
    }
}
#[cfg(test)]
mod tests2 {
    use super::*; // Import items from parent module (AesGcmCipher, AesGcmError)
    use hex;

    // --- Test Keys ---
    // 128-bit / 16 bytes
    const KEY128_HEX: &str = "000102030405060708090a0b0c0d0e0f";
    // 192-bit / 24 bytes
    const KEY192_HEX: &str = "000102030405060708090a0b0c0d0e0f1011121314151617";
    // 256-bit / 32 bytes
    const KEY256_HEX: &str = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f";

    const PLAINTEXT: &[u8] = b"This is a secret message.";
    const AAD: &[u8] = b"Associated Data";

    // --- Constructor Tests ---

    // #[test]
    // fn test_hello() {
    //     let cipher1 = AesGcmCipher::new_from_hex(KEY192_HEX).unwrap();
    //     let ciphertext = cipher1.encrypt(b"hello", b"auth").unwrap();
    //     println!("ciphertext: {}", hex::encode(&ciphertext));
    //     // let exp = "31323334353637383930313295c35b897e9b84fede69356bb54f6b7577f9ee7db1";
    //     let exp = "31323334353637383930313295c35b897e9bd24e0af9983173fb78fd352393ba9a";
    //     assert_eq!(hex::encode(&ciphertext), exp);
    // }

    #[test]
    fn test_new_valid_keys() {
        assert!(AesGcmCipher::new(&[0u8; 16]).is_ok());
        assert!(AesGcmCipher::new(&[0u8; 24]).is_ok());
        assert!(AesGcmCipher::new(&[0u8; 32]).is_ok());
    }

    #[test]
    fn test_new_invalid_key_length() {
        assert!(matches!(
            AesGcmCipher::new(&[0u8; 15]),
            Err(AesGcmError::InvalidKeyLength(15))
        ));
        assert!(matches!(
            AesGcmCipher::new(&[0u8; 17]),
            Err(AesGcmError::InvalidKeyLength(17))
        ));
        assert!(matches!(
            AesGcmCipher::new(&[0u8; 31]),
            Err(AesGcmError::InvalidKeyLength(31))
        ));
        assert!(matches!(
            AesGcmCipher::new(&[0u8; 33]),
            Err(AesGcmError::InvalidKeyLength(33))
        ));
        assert!(matches!(
            AesGcmCipher::new(&[]),
            Err(AesGcmError::InvalidKeyLength(0))
        ));
    }

    #[test]
    fn test_new_from_hex_valid() {
        assert!(AesGcmCipher::new_from_hex(KEY128_HEX).is_ok());
        assert!(AesGcmCipher::new_from_hex(KEY192_HEX).is_ok());
        assert!(AesGcmCipher::new_from_hex(KEY256_HEX).is_ok());
    }

    #[test]
    fn test_new_from_hex_invalid_chars() {
        let invalid_hex = "000102030405060708090a0b0c0d0eXX"; // XX are invalid
        let result = AesGcmCipher::new_from_hex(invalid_hex);
        assert!(result.is_err());
        assert!(matches!(result, Err(AesGcmError::InvalidKey(_))));
        // Check the contained string if needed:
        if let Err(AesGcmError::InvalidKey(s)) = result {
            assert_eq!(s, invalid_hex);
        } else {
            panic!("Expected InvalidKey error variant");
        }
    }

    #[test]
    fn test_new_from_hex_invalid_length() {
        // Corresponds to 15 bytes (invalid length)
        let invalid_hex_len = "000102030405060708090a0b0c0d0e";
        let result = AesGcmCipher::new_from_hex(invalid_hex_len);
        assert!(result.is_err());
        // It decodes successfully but then fails the length check in `new`
        assert!(matches!(result, Err(AesGcmError::InvalidKeyLength(15))));

        // Odd number of hex chars - hex::decode fails first
        let invalid_hex_odd = "000102030405060708090a0b0c0d0e0";
        let result_odd = AesGcmCipher::new_from_hex(invalid_hex_odd);
        assert!(result_odd.is_err());
        // This specific error comes from hex::decode
        assert!(matches!(result_odd, Err(AesGcmError::InvalidKey(_))));
    }

    // --- Encrypt/Decrypt Cycle Tests ---

    fn encrypt_decrypt_cycle(key_hex: &str, plaintext: &[u8], aad: &[u8]) {
        let cipher =
            AesGcmCipher::new_from_hex(key_hex).expect("Failed to create cipher from valid hex");

        // Encrypt
        let mut ciphertext = cipher.encrypt(plaintext, aad).expect("Encryption failed");
        println!("Plaintext len: {}", plaintext.len());
        println!("Ciphertext len: {}", ciphertext.len());
        println!("Nonce+Plaintext+Tag: {}", hex::encode(&ciphertext));

        // Ensure ciphertext length is correct
        let expected_len = AesGcmCipher::NONCE_SIZE + plaintext.len() + AesGcmCipher::TAG_SIZE;
        assert_eq!(ciphertext.len(), expected_len, "Ciphertext length mismatch");

        // Ensure ciphertext is different from plaintext (unless plaintext is empty)
        if !plaintext.is_empty() {
            let _plaintext_part_in_ciphertext =
                &ciphertext[AesGcmCipher::NONCE_SIZE..ciphertext.len() - AesGcmCipher::TAG_SIZE];
            // Note: Encryption might not change the buffer content immediately if plaintext is short enough
            // but the overall ciphertext (with nonce and tag) must be different.
            assert_ne!(
                ciphertext, plaintext,
                "Ciphertext should not be same as plaintext"
            );
        }

        // Decrypt
        let decrypted_plaintext_slice = cipher
            .decrypt(&mut ciphertext, aad)
            .expect("Decryption failed");

        // Verify decrypted data
        assert_eq!(
            decrypted_plaintext_slice, plaintext,
            "Decrypted plaintext does not match original"
        );

        // Verify the buffer state after in-place decryption
        // The part after nonce and before tag should now hold the plaintext
        let nonce_part = &ciphertext[..AesGcmCipher::NONCE_SIZE];
        let plaintext_part =
            &ciphertext[AesGcmCipher::NONCE_SIZE..ciphertext.len() - AesGcmCipher::TAG_SIZE];
        let tag_part = &ciphertext[ciphertext.len() - AesGcmCipher::TAG_SIZE..];

        println!("Nonce after decrypt: {}", hex::encode(nonce_part));
        println!(
            "Plaintext in buffer after decrypt: {}",
            hex::encode(plaintext_part)
        );
        println!("Tag after decrypt: {}", hex::encode(tag_part));

        assert_eq!(
            plaintext_part, plaintext,
            "Buffer does not contain plaintext after in-place decryption"
        );
    }

    #[test]
    fn test_encrypt_decrypt_128() {
        encrypt_decrypt_cycle(KEY128_HEX, PLAINTEXT, AAD);
    }

    #[test]
    fn test_encrypt_decrypt_192() {
        encrypt_decrypt_cycle(KEY192_HEX, PLAINTEXT, AAD);
    }

    #[test]
    fn test_encrypt_decrypt_256() {
        encrypt_decrypt_cycle(KEY256_HEX, PLAINTEXT, AAD);
    }

    #[test]
    fn test_encrypt_decrypt_empty_plaintext() {
        encrypt_decrypt_cycle(KEY128_HEX, b"", AAD);
        encrypt_decrypt_cycle(KEY256_HEX, b"", AAD);
    }

    #[test]
    fn test_encrypt_decrypt_empty_aad() {
        encrypt_decrypt_cycle(KEY128_HEX, PLAINTEXT, b"");
        encrypt_decrypt_cycle(KEY256_HEX, PLAINTEXT, b"");
    }

    #[test]
    fn test_encrypt_decrypt_empty_both() {
        encrypt_decrypt_cycle(KEY128_HEX, b"", b"");
        encrypt_decrypt_cycle(KEY256_HEX, b"", b"");
    }

    #[test]
    fn test_encrypt_decrypt_different_instances() {
        // Ensure decryption works with a different instance using the same key
        let cipher1 = AesGcmCipher::new_from_hex(KEY256_HEX).unwrap();
        let mut ciphertext = cipher1.encrypt(PLAINTEXT, AAD).unwrap();

        let cipher2 = AesGcmCipher::new_from_hex(KEY256_HEX).unwrap();
        let decrypted_slice = cipher2.decrypt(&mut ciphertext, AAD).unwrap();

        assert_eq!(decrypted_slice, PLAINTEXT);
    }

    // --- Decryption Failure Tests ---

    #[test]
    fn test_decrypt_wrong_key() {
        let cipher1 = AesGcmCipher::new_from_hex(KEY128_HEX).unwrap();
        let mut ciphertext = cipher1.encrypt(PLAINTEXT, AAD).unwrap();

        // Use a different (but valid) key for decryption
        let wrong_key_hex = "101112131415161718191a1b1c1d1e1f"; // Different 128-bit key
        let cipher_wrong_key = AesGcmCipher::new_from_hex(wrong_key_hex).unwrap();

        let result = cipher_wrong_key.decrypt(&mut ciphertext, AAD);
        assert!(result.is_err());
        assert!(matches!(result, Err(AesGcmError::DecryptionFailed(_))));
    }

    #[test]
    fn test_decrypt_wrong_aad() {
        let cipher = AesGcmCipher::new_from_hex(KEY128_HEX).unwrap();
        let mut ciphertext = cipher.encrypt(PLAINTEXT, AAD).unwrap();

        let wrong_aad = b"Different Associated Data";
        let result = cipher.decrypt(&mut ciphertext, wrong_aad);
        assert!(result.is_err());
        assert!(matches!(result, Err(AesGcmError::DecryptionFailed(_))));
    }

    #[test]
    fn test_decrypt_tampered_ciphertext() {
        let cipher = AesGcmCipher::new_from_hex(KEY128_HEX).unwrap();
        let mut ciphertext = cipher.encrypt(PLAINTEXT, AAD).unwrap();

        // Tamper a byte in the actual ciphertext (after nonce, before tag)
        if ciphertext.len() > AesGcmCipher::NONCE_SIZE + AesGcmCipher::TAG_SIZE {
            ciphertext[AesGcmCipher::NONCE_SIZE] ^= 0xAA; // Flip some bits
        } else {
            // If plaintext was empty, tampering ciphertext doesn't make sense,
            // tamper tag instead (tested below). We can skip this for empty plaintext.
            return;
        }

        let result = cipher.decrypt(&mut ciphertext, AAD);
        assert!(
            result.is_err(),
            "Decryption should fail with tampered ciphertext"
        );
        assert!(matches!(result, Err(AesGcmError::DecryptionFailed(_))));
    }

    #[test]
    fn test_decrypt_tampered_tag() {
        let cipher = AesGcmCipher::new_from_hex(KEY128_HEX).unwrap();
        let mut ciphertext = cipher.encrypt(PLAINTEXT, AAD).unwrap();

        // Tamper a byte in the tag (last bytes)
        let tag_start_index = ciphertext.len() - AesGcmCipher::TAG_SIZE;
        ciphertext[tag_start_index] ^= 0xAA; // Flip some bits in the first byte of the tag

        let result = cipher.decrypt(&mut ciphertext, AAD);
        assert!(result.is_err(), "Decryption should fail with tampered tag");
        assert!(matches!(result, Err(AesGcmError::DecryptionFailed(_))));
    }

    #[test]
    fn test_decrypt_tampered_nonce() {
        let cipher = AesGcmCipher::new_from_hex(KEY128_HEX).unwrap();
        let mut ciphertext = cipher.encrypt(PLAINTEXT, AAD).unwrap();

        // Tamper a byte in the nonce (first bytes)
        ciphertext[0] ^= 0xAA; // Flip some bits in the first byte of the nonce

        let result = cipher.decrypt(&mut ciphertext, AAD);
        // Tampering the nonce *usually* causes tag mismatch, thus decryption failure
        assert!(
            result.is_err(),
            "Decryption should fail with tampered nonce"
        );
        assert!(matches!(result, Err(AesGcmError::DecryptionFailed(_))));
    }

    #[test]
    fn test_decrypt_ciphertext_too_short() {
        let cipher = AesGcmCipher::new_from_hex(KEY128_HEX).unwrap();
        let mut too_short_ct = vec![0u8; AesGcmCipher::NONCE_SIZE + AesGcmCipher::TAG_SIZE - 1];

        let result = cipher.decrypt(&mut too_short_ct, AAD);
        assert!(result.is_err());
        assert!(matches!(result, Err(AesGcmError::CiphertextTooShort)));

        // Test exact minimum length (should proceed but likely fail decrypt unless plaintext empty)
        let _min_len_ct = vec![0u8; AesGcmCipher::NONCE_SIZE + AesGcmCipher::TAG_SIZE];
        // For a zero-length plaintext, a zero'd buffer might actually decrypt if the tag matches zero data.
        // Let's try with a real encrypted empty message.
        let mut actual_min_ciphertext = cipher.encrypt(b"", AAD).unwrap();
        assert_eq!(
            actual_min_ciphertext.len(),
            AesGcmCipher::NONCE_SIZE + AesGcmCipher::TAG_SIZE
        );
        // Decrypting this should work
        assert!(cipher.decrypt(&mut actual_min_ciphertext, AAD).is_ok());
    }
}
