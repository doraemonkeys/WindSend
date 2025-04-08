/// return true if connect to relay  success
pub async fn relay_main() -> bool {
    use crate::config;

    use tracing::{debug, error};

    debug!("try to connect to relay server");

    let relay_server_address = match config::read_config()
        .relay_server_address
        .parse::<std::net::SocketAddr>()
    {
        Ok(address) => address,
        Err(e) => {
            error!("parse relay server address error: {}", e);
            return false;
        }
    };

    let mut tcp_stream = match tokio::net::TcpStream::connect(relay_server_address).await {
        Ok(tcp_stream) => tcp_stream,
        Err(e) => {
            error!("connect relay server error: {}", e);
            return false;
        }
    };

    let cipher = match handshake(&mut tcp_stream).await {
        Some(cipher) => cipher,
        None => return false,
    };

    match send_connection_req(&mut tcp_stream, &cipher).await {
        Ok(_) => (),
        Err(_) => return false,
    }

    tracing::info!("connect to relay server success");

    update_relay_server_status(true);

    handle_request(tcp_stream, Some(cipher)).await;

    update_relay_server_status(false);

    true
}

pub fn update_relay_server_status(connected: bool) {
    use crate::status::RELAY_SERVER_CONNECTED;
    #[cfg(not(feature = "disable-systray-support"))]
    use crate::status::TX_UPDATE_RELAY_SERVER_CONNECTED;

    *RELAY_SERVER_CONNECTED.lock().unwrap() = connected;
    #[cfg(not(feature = "disable-systray-support"))]
    {
        let tx = TX_UPDATE_RELAY_SERVER_CONNECTED.get().unwrap();
        tx.try_send(()).ok();
    }
}

async fn send_connection_req(
    tcp_stream: &mut tokio::net::TcpStream,
    cipher: &crate::utils::encrypt::AesGcmCipher,
) -> Result<(), ()> {
    use crate::config;
    use tracing::{debug, error};

    use crate::relay::protocol::{CommonReq, ConnectionReq, RespHead};
    let req = ConnectionReq {
        common: CommonReq {
            id: config::read_config().get_device_id(),
        },
    };
    match req.write_to(tcp_stream, Some(cipher)).await {
        Ok(_) => (),
        Err(_) => return Err(()),
    }
    let head = match RespHead::read_from(tcp_stream, Some(cipher)).await {
        Ok(head) => head,
        Err(_) => return Err(()),
    };
    debug!("connection resp head: {:?}", head);
    use crate::relay::protocol::StatusCode;

    if head.code != StatusCode::Success {
        error!(
            "connection failed, code: {:?}, msg: {}",
            head.code, head.msg
        );
        return Err(());
    }
    if head.data_len != 0 {
        error!("bad response, data_len: {}", head.data_len);
        return Err(());
    }
    Ok(())
}

async fn handshake(
    conn: &mut tokio::net::TcpStream,
) -> Option<crate::utils::encrypt::AesGcmCipher> {
    use crate::config;
    use crate::relay::protocol::{HandshakeReq, HandshakeResp, StatusCode};
    use crate::utils::encrypt;
    use base64::prelude::*;
    use rand::rngs::OsRng;
    use tracing::error;
    use x25519_dalek::{EphemeralSecret, PublicKey};

    let secret = EphemeralSecret::random_from_rng(OsRng);
    let public = PublicKey::from(&secret);

    let relay_secret_key = config::read_config()
        .relay_secret_key
        .as_ref()
        .map(|s| hash_to_aes192_key(s.as_bytes()));
    let relay_secret_key_selector = relay_secret_key.map(|k| get_aes192_key_selector(&k));
    // println!("relay_secret_key_selector: {:?}", relay_secret_key_selector);
    let cipher = relay_secret_key
        .map(|k| encrypt::AesGcmCipher::new(&k))
        .map(|cipher| cipher.unwrap());
    let auth_field = "AUTH".to_string() + &encrypt::generate_rand_bytes_hex(16);
    let auth_aad = encrypt::generate_rand_bytes_hex(16);
    let auth_field_b64 = cipher
        .as_ref()
        .map(|c| c.encrypt(auth_field.as_bytes(), auth_aad.as_bytes()));
    let auth_field_b64 = match auth_field_b64 {
        Some(Ok(b)) => Some(BASE64_STANDARD.encode(b)),
        Some(Err(e)) => {
            error!("encrypt auth field error: {}", e);
            return None;
        }
        None => None,
    };

    let req = HandshakeReq {
        secret_key_selector: relay_secret_key_selector,
        auth_field_b64,
        auth_aad,
        ecdh_public_key_b64: BASE64_STANDARD.encode(public),
    };

    if req.write_to(conn).await.is_err() {
        return None;
    }

    let resp = match HandshakeResp::read_from(conn).await {
        Err(_) => return None,
        Ok(resp) => resp,
    };

    if resp.code != StatusCode::Success {
        error!("handshake failed, code: {:?}, msg: {}", resp.code, resp.msg);
        return None;
    }

    let mut ecdh_public_key = match BASE64_STANDARD.decode(resp.ecdh_public_key_b64) {
        Ok(key) => key,
        Err(e) => {
            error!("decode ecdh public key error: {}", e);
            return None;
        }
    };

    let ecdh_public_key = match cipher {
        Some(cipher) => match cipher.decrypt(&mut ecdh_public_key, b"AUTH") {
            Ok(key) => key,
            Err(e) => {
                error!("decrypt ecdh public key error: {}", e);
                return None;
            }
        },
        None => &mut ecdh_public_key,
    };

    let ecdh_public_key: [u8; 32] = match ecdh_public_key.try_into() {
        Ok(key) => key,
        Err(e) => {
            error!("convert ecdh public key to [u8; 32] error: {:?}", e);
            return None;
        }
    };
    let ecdh_public_key = PublicKey::from(ecdh_public_key);
    let shared_secret = secret.diffie_hellman(&ecdh_public_key);

    let cipher = encrypt::AesGcmCipher::new(&hash_to_aes192_key(shared_secret.as_bytes()));
    let cipher = match cipher {
        Ok(c) => c,
        Err(e) => {
            error!("create cipher error: {}", e);
            return None;
        }
    };
    Some(cipher)
}

async fn handle_request(
    mut conn: tokio::net::TcpStream,
    cipher: Option<crate::utils::encrypt::AesGcmCipher>,
) {
    use crate::relay::protocol::{Action, CommonReqHead};
    use tokio::time::Duration;
    use tracing::{debug, error};
    const READ_TIMEOUT_DURATION: Duration = Duration::from_secs(180);

    loop {
        debug!("waiting for relay server request");

        let read_future = CommonReqHead::read_from(&mut conn, cipher.as_ref());
        let read_result = tokio::time::timeout(READ_TIMEOUT_DURATION, read_future).await;
        let common_req_head = match read_result {
            Ok(Ok(head)) => head,
            Ok(Err(_)) => return,
            Err(_) => {
                error!("read relay server request timeout");
                return;
            }
        };

        match common_req_head.action {
            Action::Relay => {
                conn = match handle_relay(conn, cipher.as_ref()).await {
                    Ok(conn) => conn,
                    Err(_) => return,
                }
            }
            Action::Heartbeat => {
                match handle_heartbeat(&mut conn, common_req_head, cipher.as_ref()).await {
                    Ok(_) => (),
                    Err(_) => return,
                }
            }
            _ => {
                error!("invalid action: {:?}", common_req_head.action);
                return;
            }
        };
    }
}

async fn handle_relay(
    conn: tokio::net::TcpStream,
    _: Option<&crate::utils::encrypt::AesGcmCipher>,
) -> Result<tokio::net::TcpStream, ()> {
    use crate::config;
    use tracing::{debug, error};
    debug!("new relay connection");

    let tls_stream = match config::TLS_ACCEPTOR.accept(conn).await {
        Ok(tls_stream) => tls_stream,
        Err(err) => {
            error!("tls accept error: {}", err);
            return Err(());
        }
    };
    debug!("relay tls accept success");
    let conn = match crate::route::main_process(tls_stream).await {
        Some(conn) => conn,
        None => return Err(()),
    };
    debug!("relay route success");
    let (io, _) = conn.into_inner();
    Ok(io)
}

async fn handle_heartbeat(
    conn: &mut tokio::net::TcpStream,
    head: crate::relay::protocol::CommonReqHead,
    cipher: Option<&crate::utils::encrypt::AesGcmCipher>,
) -> Result<(), ()> {
    use crate::relay::protocol::{Action, HeartbeatReq, RespHead, StatusCode};
    if head.data_len == 0 {
        return Ok(());
    }

    let heartbeat_req = HeartbeatReq::read_from(conn, head.data_len, cipher).await?;
    if heartbeat_req.need_resp {
        let resp_head = RespHead {
            code: StatusCode::Success,
            msg: "".to_string(),
            action: Action::Heartbeat,
            data_len: 0,
        };
        match resp_head.write_to(conn, cipher).await {
            Ok(_) => (),
            Err(_) => return Err(()),
        }
    }
    Ok(())
}

fn hash_to_aes192_key(c: &[u8]) -> [u8; 24] {
    use crate::utils::encrypt;
    let hash = encrypt::compute_sha256(c);
    hash[..24].try_into().unwrap()
}

fn get_aes192_key_selector(key: &[u8; 24]) -> String {
    use crate::utils::encrypt;
    let hash = encrypt::compute_sha256(key);
    hex::encode(&hash[..4])
}
