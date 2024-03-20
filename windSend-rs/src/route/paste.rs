use crate::route::resp::{resp_common_error_msg, send_msg, send_msg_with_body};
use crate::route::{RouteDataType, RouteRecvHead};
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
        let clipboard = &mut crate::config::CLIPBOARD.lock().unwrap();
        let r = clipboard.set_text(body.clone());
        if let Err(e) = r {
            error!("set clipboard text failed, err: {}", e);
        }
    }
    crate::utils::inform(&body, &head.device_name);
    send_msg(conn, &"粘贴成功".to_string()).await.ok();
}

pub async fn sync_text_handler(conn: &mut TlsStream<TcpStream>, head: RouteRecvHead) {
    let cur_clipboard_text = crate::config::CLIPBOARD.lock().unwrap().get_text();
    if head.data_len > 0 {
        let mut body_buf = vec![0u8; head.data_len as usize];
        let r = conn.read_exact(&mut body_buf).await;
        if let Err(e) = r {
            error!("read body failed, err: {}", e);
        }
        let body = String::from_utf8_lossy(&body_buf);
        debug!("paste text data: {}", body);
        {
            let clipboard = &mut crate::config::CLIPBOARD.lock().unwrap();
            let r = clipboard.set_text(body);
            if r.is_err() && cur_clipboard_text.is_err() {
                let msg = format!("set clipboard text failed, err: {}", r.unwrap_err());
                error!("{}", msg);
                let _ = resp_common_error_msg(conn, &msg);
                return;
            }
        }
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

/// 返回是否应该继续循环(比如没有遇到Socket Error)
pub async fn paste_file_handler(conn: &mut TlsStream<TcpStream>, head: RouteRecvHead) -> bool {
    if let crate::route::PathInfoType::Dir = head.upload_type {
        return create_dirs_only_handler(conn, head).await;
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
    if head.files_count_in_this_op == 0 {
        let err_msg = &format!(
            "invalid file part, FilesCountInThisOp:{}",
            head.files_count_in_this_op
        );
        error!("{}", err_msg);
        return resp_common_error_msg(conn, err_msg).await.is_ok();
    }
    // let file = (*crate::file::GLOBAL_FILE_RECEIVER).clone().borrow_mut();
    let file = crate::file::GLOBAL_FILE_RECEIVER.get_file(&head).await;
    if let Err(err) = file {
        error!("create file error: {}", err);
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
    // 8 is a magic number
    let buf_size = std::cmp::max((data_len / 8) as usize, 4096);
    let (conn_reader, mut conn_writer) = tokio::io::split(conn);
    // let mut reader =
    //     tokio::io::BufReader::with_capacity(buf_size, conn_reader.take(data_len as u64));
    let mut buf_writer = tokio::io::BufWriter::with_capacity(buf_size, &mut file_writer);
    // rust需要写缓冲速度才会上来，go读缓冲速度最快。
    // rust只开启读缓冲或同时开启写缓冲和读缓冲速度都很慢。
    let n = tokio::io::copy(&mut conn_reader.take(data_len as u64), &mut buf_writer).await;
    // let n = tokio::io::copy(&mut reader, &mut file_writer).await;
    if let Err(err) = buf_writer.flush().await {
        error!("flush file writer failed, err: {}", err);
        return resp_common_error_msg(
            &mut conn_writer,
            &format!("flush file writer failed, err: {}", err),
        )
        .await
        .is_ok();
    }
    if let Err(err) = n {
        let msg = format!("write file error: {}", err);
        error!("{}", msg);
        let resp_success = resp_common_error_msg(&mut conn_writer, &msg).await.is_ok();
        crate::file::GLOBAL_FILE_RECEIVER
            .report_file_part(head.file_id, head.start, head.end, Some(msg))
            .await;
        return resp_success;
    }
    let n = n.unwrap();
    if n < data_len as u64 {
        let msg = format!("write file error, n: {}, dataLen: {}", n, data_len);
        error!("{}", msg);
        let resp_success = resp_common_error_msg(&mut conn_writer, &msg).await.is_ok();
        crate::file::GLOBAL_FILE_RECEIVER
            .report_file_part(head.file_id, head.start, head.end, Some(msg))
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
    let (done, err_occurred) = crate::file::GLOBAL_FILE_RECEIVER
        .report_file_part(head.file_id, head.start, head.end, None)
        .await;
    if err_occurred {
        return resp_success;
    }
    if done {
        info!("save file success: {}", head.path);
    }
    resp_success
}

pub async fn create_dirs_only_handler(
    conn: &mut TlsStream<TcpStream>,
    head: RouteRecvHead,
) -> bool {
    let mut data_buf = vec![0u8; head.data_len as usize];
    if let Err(e) = conn.read_exact(&mut data_buf).await {
        error!("read body failed, err: {}", e);
        return false;
    }
    let dirs: Vec<String> = match serde_json::from_slice(&data_buf) {
        Ok(dirs) => dirs,
        Err(e) => {
            error!("parse dirs failed, err: {}", e);
            return false;
        }
    };

    let download_dir = std::path::PathBuf::from(
        crate::config::GLOBAL_CONFIG
            .lock()
            .unwrap()
            .save_path
            .clone(),
    );
    for dir in &dirs {
        let r = tokio::fs::create_dir_all(download_dir.join(dir)).await;
        if let Err(err) = r {
            error!("create dir error: {}", err);
            return resp_common_error_msg(conn, &err.to_string()).await.is_ok();
        }
    }
    if (send_msg(conn, &"create dirs success".to_string()).await).is_err() {
        return false;
    };
    if !dirs.is_empty() && head.files_count_in_this_op == 0 {
        crate::utils::inform("目录创建成功", &head.device_name);
    }
    true
}
