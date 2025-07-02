use tracing::debug;

pub static BASE_WEB_URL: &str = "https://ko0.com";
pub static SUBMIT_URL: &str = "https://ko0.com/submit/";
pub static USER_AGENT: &str = "Mozilla/5.0 (Windows NT 6.1; WOW64) \
    AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.71 Safari/537.36Mozilla/5.0 \
    (X11; Linux x86_64) AppleWebKit/537.11 (KHTML, like Gecko) Chrome/23.0.1271.64 \
    Safari/537.11Mozilla/5.0 (Windows; U; Windows NT 6.1; en-US) AppleWebKit/534.16 \
    (KHTML, like Gecko) Chrome/10.0.648.133 Safari/534.16";

lazy_static::lazy_static!(
    pub static ref MY_URL: String = init_my_url();
);

fn init_my_url() -> String {
    let secret_key_hex = crate::config::GLOBAL_CONFIG
        .read()
        .unwrap()
        .secret_key_hex
        .clone();
    let r_key = secret_key_hex.as_bytes();
    let r_key = crate::utils::encrypt::compute_sha256(r_key);
    let r_key = crate::utils::encrypt::compute_sha256(&r_key);
    let r_key_hex = hex::encode(r_key);
    let my_url = format!("{}/{}", BASE_WEB_URL, &r_key_hex[0..16]);
    tracing::info!("my_url: {}", my_url);
    my_url
}

pub async fn get_content_from_web() -> Result<Vec<u8>, Box<dyn std::error::Error>> {
    let client = reqwest::Client::new();
    let resp = client
        .get(&*MY_URL)
        .header("User-Agent", USER_AGENT)
        .send()
        .await?;
    let body_text = resp.text().await?;
    let re = regex::Regex::new(r#"class[\s]*=[\s]*"txt_view">[\s]*<p>(.+)<\/p>"#)?;
    let matchs = re.captures(&body_text).ok_or("can not find content")?;
    debug!("{:?}", matchs);
    let mut encrypted_data = hex::decode(matchs.get(1).unwrap().as_str())?;
    let decrypt_data = crate::config::get_cipher()?.decrypt(&mut encrypted_data, "".as_bytes())?;
    Ok(decrypt_data.to_vec())
}

pub async fn post_content_to_web(context: &[u8]) -> Result<(), Box<dyn std::error::Error>> {
    let encrypted_data = crate::config::get_cipher()?.encrypt(context, "".as_bytes())?;
    let encrypted_data_hex = hex::encode(&encrypted_data);
    let client = reqwest::ClientBuilder::new()
        .cookie_store(true)
        .build()
        .unwrap();
    let csrfmiddlewaretoken = get_post_csrfmiddlewaretoken(&client).await?;
    let mut payload = reqwest::multipart::Form::new();
    debug!("csrfmiddlewaretoken: {}", csrfmiddlewaretoken);
    let my_url = (*MY_URL).replace('\\', "/");
    let post_code = my_url
        .split('/')
        .next_back()
        .ok_or_else(|| format!("invalid post url: {my_url}"))?
        .to_string();
    debug!("post_code: {}", post_code);
    payload = payload.text("csrfmiddlewaretoken", csrfmiddlewaretoken);
    payload = payload.text("txt", encrypted_data_hex);
    payload = payload.text("code", post_code);
    payload = payload.text("sub_type", "T");
    payload = payload.text("file", "");
    let resp = client
        .post(SUBMIT_URL)
        .header("Referer", &*MY_URL)
        .header("User-Agent", USER_AGENT)
        .multipart(payload)
        .send()
        .await?;
    let body_text = resp.text().await?;
    debug!("{}", body_text);
    if !body_text.contains("success") {
        return Err("post content failed".into());
    }
    Ok(())
}

async fn get_post_csrfmiddlewaretoken(
    client: &reqwest::Client,
) -> Result<String, Box<dyn std::error::Error>> {
    let resp = client
        .get(&*MY_URL)
        .header("User-Agent", USER_AGENT)
        .send()
        .await?;
    let body_text = resp.text().await?;
    parse_csrfmiddlewaretoken(&body_text)
}

fn parse_csrfmiddlewaretoken(content: &str) -> Result<String, Box<dyn std::error::Error>> {
    let re = regex::Regex::new(r#"name="csrfmiddlewaretoken" value="(.+)">"#)?;
    let matchs = re
        .captures(content)
        .ok_or("can not find csrfmiddlewaretoken")?;
    Ok(matchs.get(1).unwrap().as_str().to_string())
}
