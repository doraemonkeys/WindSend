use aes::cipher::{block_padding::Pkcs7, BlockDecryptMut, BlockEncryptMut, KeyIvInit};
// use anyhow::Ok;
use rand::thread_rng;
// use rand::CryptoRng;
// use rand::Rng;
use rand::RngCore;
use sha2::Digest;

pub fn rand_n_bytes(rng: &mut rand::rngs::ThreadRng, n: usize) -> Vec<u8> {
    let mut bytes = vec![0u8; n];
    rng.fill_bytes(&mut bytes);
    bytes
}

pub fn rand_n_bytes2(n: usize) -> Vec<u8> {
    let mut bytes = vec![0u8; n];
    thread_rng().fill_bytes(&mut bytes);
    bytes
}

pub fn generate_secret_key_hex(byte_len: usize) -> String {
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
