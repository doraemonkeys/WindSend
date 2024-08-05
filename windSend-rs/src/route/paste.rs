use crate::language::LanguageKey;
use crate::route::resp::{resp_common_error_msg, send_msg, send_msg_with_body};
use crate::route::{RouteDataType, RouteRecvHead};
use std::borrow::Cow;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio_rustls::server::TlsStream;
use tracing::{debug, error, info, warn};

pub async fn paste_text_handler(conn: &mut TlsStream<TcpStream>, head: RouteRecvHead) {
    let mut body_buf = vec![0u8; head.data_len as usize];
    let r = conn.read_exact(&mut body_buf).await;
    if let Err(e) = r {
        error!("read body failed, err: {}", e);
    }
    let body = String::from_utf8_lossy(&body_buf);
    debug!("paste text data: {}", body);
    {
        let r = crate::config::CLIPBOARD
            .with_clipboard(|clipboard| clipboard.set_text(Cow::clone(&body)));
        if let Err(e) = r {
            error!("set clipboard text failed, err: {}", e);
        }
    }
    if body.trim().starts_with("http") || body.trim().starts_with("https") {
        crate::utils::inform(&body, &head.device_name, Some(&body));
    } else {
        crate::utils::inform(&body, &head.device_name, None);
    }
    send_msg(conn, &"粘贴成功".to_string()).await.ok();
}

pub async fn sync_text_handler(conn: &mut TlsStream<TcpStream>, head: RouteRecvHead) {
    // let cur_clipboard_text = crate::config::CLIPBOARD.lock().unwrap().get_text();
    let mut body: Option<_> = None;
    let mut body_buf = vec![0u8; head.data_len as usize];
    if head.data_len > 0 {
        let r = conn.read_exact(&mut body_buf).await;
        if let Err(e) = r {
            error!("read body failed, err: {}", e);
        }
        body = Some(String::from_utf8_lossy(&body_buf));
        debug!("paste text data: {}", body.as_ref().unwrap());
    }

    let mut cur_clipboard_text: Result<_, arboard::Error> = Ok("".to_string());
    let f = |clipboard: &mut arboard::Clipboard| {
        cur_clipboard_text = clipboard.get_text();
        if let Some(body) = body {
            // 与当前剪贴板内容相同则不设置，避免触发剪贴板变化事件
            if cur_clipboard_text.is_ok() && cur_clipboard_text.as_ref().unwrap() == &body {
                return Ok(());
            }
            if let Err(e) = clipboard.set_text(body) {
                let msg = format!("set clipboard text failed, err: {}", e);
                error!("{}", msg);
                if cur_clipboard_text.is_err() {
                    return Err(msg);
                }
            }
        }
        Ok(())
    };
    if let Err(e) = crate::config::CLIPBOARD.with_clipboard(f) {
        let _ = resp_common_error_msg(conn, &e).await;
        return;
    }
    send_msg_with_body(
        conn,
        &"".to_string(),
        RouteDataType::Text,
        cur_clipboard_text.unwrap_or_default().as_ref(),
    )
    .await
    .ok();
}

/// return whether should continue loop(like no socket error)
pub async fn paste_file_handler(conn: &mut TlsStream<TcpStream>, head: RouteRecvHead) -> bool {
    if let crate::route::UploadType::UploadInfo = head.upload_type {
        return paste_file_operation_handler(conn, head).await;
    }

    // head.End == 0 && head.Start == 0 表示文件为空
    if head.end <= head.start && !(head.end == 0 && head.start == 0) {
        let err_msg = &format!("invalid file part, start:{}, end:{}", head.start, head.end);
        error!("{}", err_msg);
        return resp_common_error_msg(conn, err_msg).await.is_ok();
    }
    let data_len = head.end - head.start;
    if head.data_len != data_len {
        let err_msg = &format!(
            "invalid file part, dataLen:{}, start:{}, end:{}",
            head.data_len, head.start, head.end
        );
        error!("{}", err_msg);
        return resp_common_error_msg(conn, err_msg).await.is_ok();
    }

    // let file = (*crate::file::GLOBAL_FILE_RECEIVER).clone().borrow_mut();
    let file = crate::file::GLOBAL_RECEIVER_SESSION_MANAGER
        .setup_file_reception(&head)
        .await;
    if let Err(err) = file {
        error!("create file: {} error: {}", head.path, err);
        let _ = tokio::io::copy(&mut conn.take(head.data_len as u64), &mut tokio::io::sink()).await;
        return resp_common_error_msg(conn, &format!("create file error: {}", err))
            .await
            .is_ok();
    }
    let file = file.unwrap();
    let file_writer =
        crate::file::FilePartWriter::new(file, head.start as usize, head.end as usize).await;
    if let Err(err) = file_writer {
        error!("new file writer failed, err: {}", err);
        return resp_common_error_msg(conn, &format!("new file writer failed, err: {}", err))
            .await
            .is_ok();
    }
    let mut file_writer = file_writer.unwrap();

    let progress_handle = crate::file::GLOBAL_RECEIVER_SESSION_MANAGER
        .get_op_progress_handle(head.op_id)
        .await
        .unwrap();

    file_writer = file_writer.set_on_pull_write_ok(move |data: &[u8]| {
        if !data.is_empty() {
            use std::sync::atomic::Ordering::Relaxed;
            progress_handle
                .current_pos
                .fetch_add(data.len() as u64, Relaxed);
        }
    });

    let (conn_reader, mut conn_writer) = tokio::io::split(conn);
    // 8 is a magic number
    // let write_buf_size = std::cmp::max((data_len / 8) as usize, 4096);
    // let write_buf_size = std::cmp::min(write_buf_size, 50 * 1024 * 1024);
    let mut write_buf_size = std::cmp::min(data_len, 4 * 1024 * 1024) as usize;
    if (data_len / 8) > (4 * 1024 * 1024) && (data_len / 8) < (10 * 1024 * 1024) {
        write_buf_size = (data_len / 8) as usize;
    }
    // let write_buf_size = std::cmp::min(write_buf_size, 50 * 1024 * 1024);
    // let copy_buffer_size = std::cmp::min(data_len, 3 * 1024 * 1024) as usize;
    // let mut conn_buf_reader =
    //     tokio::io::BufReader::with_capacity(copy_buffer_size, conn_reader.take(data_len as u64));
    let mut file_buf_writer = tokio::io::BufWriter::with_capacity(write_buf_size, &mut file_writer);

    // rust需要写缓冲速度才会上来。
    // rust只开启读缓冲或同时开启写缓冲和读缓冲速度都很慢。
    let n = tokio::io::copy(&mut conn_reader.take(data_len as u64), &mut file_buf_writer).await;
    // let n = tokio::io::copy_buf(&mut conn_buf_reader, &mut file_buf_writer).await;
    if let Err(err) = n {
        let msg = format!("write file error: {}", err);
        error!("{}", msg);
        let resp_success = resp_common_error_msg(&mut conn_writer, &msg).await.is_ok();
        crate::file::GLOBAL_RECEIVER_SESSION_MANAGER
            .report_file_part_completion(head.file_id, head.start, head.end, Some(msg))
            .await;
        return resp_success;
    }
    let n = n.unwrap();
    if let Err(err) = file_buf_writer.flush().await {
        error!("flush file writer failed, err: {}", err);
        return resp_common_error_msg(
            &mut conn_writer,
            &format!("flush file writer failed, err: {}", err),
        )
        .await
        .is_ok();
    }
    if n < data_len as u64 {
        let msg = format!("write file error, n: {}, dataLen: {}", n, data_len);
        error!("{}", msg);
        let resp_success = resp_common_error_msg(&mut conn_writer, &msg).await.is_ok();
        crate::file::GLOBAL_RECEIVER_SESSION_MANAGER
            .report_file_part_completion(head.file_id, head.start, head.end, Some(msg))
            .await;
        return resp_success;
    }
    if n > data_len as u64 {
        // should not happen
        warn!("write file error, n: {}, dataLen: {}", n, data_len);
    }
    // part written successfully
    let resp_success = send_msg(
        &mut conn_writer,
        &format!(
            "file part written successfully, fileID:{}, start:{}, end:{}",
            head.file_id, head.start, head.end
        ),
    )
    .await
    .is_ok();
    debug!(
        "write file part success, fileID: {}, start: {}, end: {}",
        head.file_id, head.start, head.end
    );
    let (done, err_occurred) = crate::file::GLOBAL_RECEIVER_SESSION_MANAGER
        .report_file_part_completion(head.file_id, head.start, head.end, None)
        .await;
    if err_occurred {
        return resp_success;
    }
    if done {
        info!("save file success: {}", head.path);
    }
    resp_success
}

async fn paste_file_operation_handler(
    conn: &mut TlsStream<TcpStream>,
    head: RouteRecvHead,
) -> bool {
    let mut data_buf = vec![0u8; head.data_len as usize];
    if let Err(e) = conn.read_exact(&mut data_buf).await {
        error!("read body failed, err: {}", e);
        return false;
    }
    let op_info: crate::route::UploadOperationInfo = match serde_json::from_slice(&data_buf) {
        Ok(info) => info,
        Err(e) => {
            error!("parse upload operation info failed, err: {}", e);
            return false;
        }
    };

    debug!("paste file operation info: {:?}", op_info);

    if let Err(e) = crate::file::GLOBAL_RECEIVER_SESSION_MANAGER
        .create_op_info(&head, &op_info)
        .await
    {
        error!("create op info failed, err: {}", e);
        return resp_common_error_msg(conn, &e).await.is_ok();
    };

    let save_path = crate::config::GLOBAL_CONFIG
        .read()
        .unwrap()
        .save_path
        .clone(); // clone to avoid lock
    let download_dir = std::path::PathBuf::from(&save_path);

    use crate::utils::NormalizePath;
    if let Some(empty_dir) = &op_info.empty_dirs {
        for dir in empty_dir {
            let dir = dir.normalize_path();
            let r = tokio::fs::create_dir_all(download_dir.join(dir)).await;
            if let Err(err) = r {
                error!("create dir error: {}", err);
                return resp_common_error_msg(conn, &err.to_string()).await.is_ok();
            }
        }
    }
    if (send_msg(conn, &"create dirs success".to_string()).await).is_err() {
        return false;
    };
    if op_info.empty_dirs.is_some() && op_info.files_count_in_this_op == 0 {
        crate::utils::inform(
            LanguageKey::DirCreatedSuccessfully.translate(),
            &head.device_name,
            Some(&save_path),
        );
    }
    true
}
