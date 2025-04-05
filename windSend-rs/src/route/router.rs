use crate::route::transfer::resp_error_msg;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tokio::io::AsyncReadExt;
use tokio::net::TcpStream;
use tokio_rustls::server::TlsStream;
use tracing::info;
use tracing::{debug, error, trace, warn};

use crate::route::protocol::*;

pub async fn main_process(mut conn: TlsStream<TcpStream>) -> Option<TlsStream<TcpStream>> {
    loop {
        let head = common_auth(&mut conn).await;
        if head.is_err() {
            return None;
        }
        let head = head.unwrap();
        info!("recv head: {:?}", head);

        let mut ok = false;
        match head.action {
            RouteAction::Ping => {
                let _ = crate::route::transfer::ping_handler(&mut conn, head).await;
            }
            RouteAction::PasteText => {
                crate::route::paste::paste_text_handler(&mut conn, head).await;
            }
            RouteAction::PasteFile => {
                ok = crate::route::paste::paste_file_handler(&mut conn, head).await;
            }
            RouteAction::Copy => {
                crate::route::copy::copy_handler(&mut conn).await;
                println!("copy handler");
            }
            RouteAction::Download => {
                ok = crate::route::copy::download_handler(&mut conn, head).await;
            }
            RouteAction::Match => {
                let _ = match_handler(&mut conn).await;
            }
            RouteAction::SyncText => {
                crate::route::paste::sync_text_handler(&mut conn, head).await;
            }
            RouteAction::SetRelayServer => {
                let _ = set_relay_server_handler(&mut conn, head).await;
            }
            RouteAction::EndConnection => {
                return Some(conn);
            }
            RouteAction::Unknown(action) => {
                let msg = format!("unknown action: {:?}", action);
                let _ = crate::route::transfer::resp_common_error_msg(&mut conn, &msg).await;
                error!("{}", msg);
            }
        }
        use tokio::io::AsyncWriteExt;
        if let Err(e) = conn.flush().await {
            error!("flush failed, err: {}", e);
            return None;
        }
        if !ok {
            return Some(conn);
        }
    }
}

pub async fn common_auth(conn: &mut TlsStream<TcpStream>) -> Result<RouteRecvHead, ()> {
    const UNAUTHORIZED_CODE: i32 = 401;
    // The header cannot exceed 10KB to prevent malicious attacks from causing memory overflow
    const MAX_HEAD_LEN: isize = 1024 * 10;

    let remote_addr = conn
        .get_ref()
        .0
        .peer_addr()
        .map_err(|e| error!("get peer addr failed, err: {}", e))
        .unwrap_or(std::net::SocketAddr::from(([0, 0, 0, 0], 0)));
    debug!("try to read head, remote ip: {}", remote_addr);

    // Read the length of the json
    let mut head_len = [0u8; 4];
    if let Err(e) = conn.read_exact(&mut head_len).await {
        match e.kind() {
            std::io::ErrorKind::UnexpectedEof => info!("client {} closed", remote_addr),
            _ => error!("read head len failed, err: {}", e),
        }
        return Err(());
    }
    let head_len = i32::from_le_bytes(head_len);
    if head_len > MAX_HEAD_LEN as i32 || head_len <= 0 {
        error!("invalid head len: {}", head_len);
        return Err(());
    }
    let mut head_buf = vec![0u8; head_len as usize];
    trace!("head_len: {}", head_len);
    // Read the json
    conn.read_exact(&mut head_buf)
        .await
        .map_err(|e| error!("read head failed, err: {}", e))?;
    debug!("head_buf: {:?}", String::from_utf8_lossy(&head_buf));
    let head: RouteRecvHead = serde_json::from_slice(&head_buf)
        .map_err(|e| error!("json unmarshal failed, err: {}", e))?;

    if let RouteAction::Match = head.action {
        if *crate::config::ALLOW_TO_BE_SEARCHED.lock().unwrap() {
            return Ok(head);
        }
        let msg = format!(
            "search not allowed, deviceName: {}, ip: {}",
            head.device_name,
            remote_addr.ip()
        );
        warn!("{}", msg);
        let _ = resp_error_msg(conn, UNAUTHORIZED_CODE, &msg).await;
        return Err(());
    }

    if head.time_ip.is_empty() {
        let msg = format!("time-ip field is empty, remote ip: {}", remote_addr.ip());
        error!(msg);
        let _ = resp_error_msg(conn, UNAUTHORIZED_CODE, &msg).await;
        return Err(());
    }
    // debug!("head: {:?}", head);

    let time_and_ip_bytes =
        hex::decode(&head.time_ip).map_err(|e| error!("hex decode failed, err: {}", e))?;
    let decrypted = crate::config::get_cryptor()
        .map_err(|e| error!("get_cryptor failed, err: {}", e))?
        .decrypt(&time_and_ip_bytes);

    if let Err(e) = decrypted {
        let msg = format!(
            "decrypt failed, err: {}, remote_ip: {}",
            e,
            remote_addr.ip()
        );
        info!(msg);
        let _ = resp_error_msg(conn, UNAUTHORIZED_CODE, &msg).await;
        return Err(());
    }
    let decrypted = decrypted.unwrap();

    let time_and_ip_str =
        String::from_utf8(decrypted).map_err(|e| error!("utf8 decode failed, err: {}", e))?;
    let time_len = EXAMINE_TIME_STR.len();
    if time_and_ip_str.len() < time_len {
        let msg = format!("time-ip is too short, remote_ip: {}", remote_addr.ip());
        error!(msg);
        let _ = resp_error_msg(conn, UNAUTHORIZED_CODE, &msg).await;
        return Err(());
    }
    let time_str = &time_and_ip_str[..time_len];
    // The original address of the remote access
    let remote_access_host = &time_and_ip_str[time_len + 1..];
    trace!(
        "time_str: {}, remote access host: {}",
        time_str, remote_access_host
    );
    Ok(head)
    // let t = chrono::NaiveDateTime::parse_from_str(time_str, TIME_FORMAT)
    //     .map_err(|e| error!("parse time failed, err: {}", e))?;
    // let now = chrono::Utc::now();
    // // Replay attack, if the time difference is greater than MAX_TIME_DIFF seconds, it is considered that the time has expired
    // if now.signed_duration_since(t.and_utc()).num_seconds() > MAX_TIME_DIFF {
    //     // The problem that cannot be solved: the clock synchronization problem of timestamp verification
    //     let msg = format!("time expired! recv time: {}, local time: {}", t, now);
    //     debug!(msg);
    //     let _ = resp_error_msg(conn, UNAUTHORIZED_CODE, &msg).await;
    //     return Err(());
    // }
    // let myip = conn
    //     .get_ref()
    //     .0
    //     .local_addr()
    //     .map_err(|e| error!("get local addr failed, err: {}", e))?
    //     .ip()
    //     .to_string();
    // let myip = myip.strip_prefix("::ffff:").unwrap_or(myip.as_str());
    // let remote_ip = remote_addr.ip().to_string();
    // let remote_ip = remote_ip
    //     .strip_prefix("::ffff:")
    //     .unwrap_or(remote_ip.as_str());
    // debug!(
    //     "remote access host: {}, remote ip: {}, my ip: {}",
    //     remote_access_host, remote_ip, myip
    // );
    // let mut rah = remote_access_host;
    // if rah.contains('%') {
    //     rah = &rah[..rah.find('%').unwrap()];
    // }
    // if rah == myip {
    //     return Ok(head);
    // }

    // {
    //     let external_ips = &GLOBAL_CONFIG.read().unwrap().external_ips;
    //     if external_ips.is_some() && external_ips.as_ref().unwrap().contains(&rah.to_string()) {
    //         return Ok(head);
    //     }
    // }
    // {
    //     let trh = &GLOBAL_CONFIG.read().unwrap().trusted_remote_hosts;
    //     // dbg!(trh);
    //     // dbg!(remote_ip.to_string());
    //     if trh.is_some() && trh.as_ref().unwrap().contains(&remote_ip.to_string()) {
    //         return Ok(head);
    //     }
    // }
    // let msg = format!("ip not match: {} != {}", remote_access_host, myip);
    // error!(msg);
    // let _ = resp_error_msg(conn, UNAUTHORIZED_CODE, &msg).await;
    // Err(())
}

async fn match_handler(conn: &mut TlsStream<TcpStream>) -> Result<(), ()> {
    let hostname = hostname::get()
        .map_err(|e| error!("get hostname failed, err: {}", e))
        .unwrap_or_default();
    let hostname: String = hostname.to_string_lossy().to_string();
    let ca_certificate = match crate::config::read_ca_certificate_pem() {
        Ok(ca_certificate) => ca_certificate,
        Err(e) => {
            error!("read ca certificate failed, err: {}", e);
            let _ = crate::route::transfer::resp_common_error_msg(conn, &e.to_string()).await;
            return Err(());
        }
    };
    let action_resp = MatchActionRespBody {
        device_name: hostname,
        secret_key_hex: crate::config::GLOBAL_CONFIG
            .read()
            .unwrap()
            .secret_key_hex
            .clone(),
        ca_certificate,
    };
    let action_resp = serde_json::to_vec(&action_resp);
    if let Err(e) = &action_resp {
        let err = format!("json marshal failed, err: {}", e);
        error!("{}", err);
        let _ = crate::route::transfer::resp_common_error_msg(conn, &err).await;
        return Err(());
    }
    let r =
        crate::route::transfer::send_msg(conn, &String::from_utf8(action_resp.unwrap()).unwrap())
            .await;
    match r {
        Ok(_) => {
            #[cfg(not(feature = "disable-systray-support"))]
            if let Err(e) = crate::status::TX_CLOSE_QUICK_PAIR
                .get()
                .unwrap()
                .try_send(())
            {
                error!("send close allow to be search failed, err: {}", e);
            }
            *crate::config::ALLOW_TO_BE_SEARCHED.lock().unwrap() = false;
            cancel_allow_to_be_searched_in_config();
            info!("turn off the switch of allowing to be searched");
            Ok(())
        }
        Err(e) => Err(e),
    }
}

fn cancel_allow_to_be_searched_in_config() {
    if !crate::config::GLOBAL_CONFIG
        .read()
        .unwrap()
        .allow_to_be_searched_once
    {
        return;
    }
    let mut cnf = crate::config::GLOBAL_CONFIG.write().unwrap();
    cnf.allow_to_be_searched_once = false;
    cnf.save().expect("save config file error");
}

async fn set_relay_server_handler(conn: &mut TlsStream<TcpStream>, head: RouteRecvHead) {
    use crate::config;
    use crate::route::transfer::{resp_common_error_msg, send_msg};

    let mut body_buf = vec![0u8; head.data_len as usize];
    let r = conn.read_exact(&mut body_buf).await;
    if let Err(e) = r {
        error!("read body failed, err: {}", e);
        let _ = resp_common_error_msg(conn, &e.to_string()).await;
        return;
    }
    let req: SetRelayServerReq = match serde_json::from_slice(&body_buf) {
        Ok(req) => req,
        Err(e) => {
            error!("json unmarshal failed, err: {}", e);
            let _ = resp_common_error_msg(conn, &e.to_string()).await;
            return;
        }
    };
    debug!("set relay server req: {:?}", req);
    if req.enable_relay && req.relay_server_address.is_empty() {
        let msg = String::from("invalid relay server address");
        error!("set relay server failed, {}", msg);
        let _ = resp_common_error_msg(conn, &msg).await;
        return;
    }
    let err;
    {
        let mut cnf = config::write_config();
        cnf.relay_server_address = req.relay_server_address.clone();
        cnf.relay_secret_key = req.relay_secret_key.clone();
        cnf.enable_relay = req.enable_relay;
        err = cnf.save();
    }
    if let Err(e) = err {
        error!("save config failed, err: {}", e);
        let _ = resp_common_error_msg(conn, &e).await;
        return;
    }
    if let Err(_) = send_msg(conn, &"success".to_string()).await {
        error!("send success msg failed");
    }

    if req.enable_relay {
        crate::relay::run::tick_relay();
    }
}
