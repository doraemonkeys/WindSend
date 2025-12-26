use crate::language::LanguageKey;
use crate::route::protocol::{RouteDataType, RouteRecvHead};
use crate::route::transfer::{resp_common_error_msg, send_msg, send_msg_with_body};
use regex::bytes::Regex;
use std::borrow::Cow;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio_rustls::server::TlsStream;
use tracing::{debug, error, info, warn};

static URL_REGEX: std::sync::LazyLock<Regex> =
    std::sync::LazyLock::new(|| Regex::new(r"https?://[^ \r\n]+").unwrap());

pub async fn paste_text_handler(conn: &mut TlsStream<TcpStream>, head: RouteRecvHead) {
    let mut body_buf = vec![0u8; head.data_len as usize];
    let r = conn.read_exact(&mut body_buf).await;
    if let Err(e) = r {
        error!("read body failed, err: {}", e);
        return;
    }
    let body = String::from_utf8_lossy(&body_buf);
    debug!("paste text data: {}", body);

    if let Err(e) = crate::config::CLIPBOARD.write_text(Cow::clone(&body)) {
        error!("set clipboard text failed, err: {}", e);
        resp_common_error_msg(conn, &format!("set clipboard failed, err: {e}"))
            .await
            .ok();
        return;
    }
    send_msg(conn, &"Paste success".to_string()).await.ok();

    let mut notification_url: Option<&str> = None;
    const URL_SEARCH_LIMIT: usize = 300;

    if (body.trim_start().starts_with("http") || body.len() <= URL_SEARCH_LIMIT)
        && let Some(m) = URL_REGEX.find(body.as_bytes())
    {
        notification_url = std::str::from_utf8(m.as_bytes()).ok();
    }

    crate::utils::inform(&body, &head.device_name, notification_url);
}

/// Returns whether should continue loop (like no socket error)
pub async fn sync_content_handler(conn: &mut TlsStream<TcpStream>, head: RouteRecvHead) -> bool {
    // For file parts (File/Dir), use paste_file_handler for proper acknowledgment
    if matches!(
        head.upload_type,
        crate::route::protocol::UploadType::File | crate::route::protocol::UploadType::Dir
    ) {
        return paste_file_handler(conn, head).await;
    }

    // For UploadInfo, handle the operation and then send clipboard content
    if matches!(
        head.upload_type,
        crate::route::protocol::UploadType::UploadInfo
    ) {
        if !sync_file_operation_handler(conn, &head).await {
            return false;
        }
        return send_clipboard_response(conn).await;
    }

    // Handle clipboard image sync
    if matches!(head.sync_data_type, RouteDataType::ClipImage) {
        return sync_clipboard_image_handler(conn, &head).await;
    }

    // Handle text sync
    let mut body: Option<_> = None;
    let mut body_buf = vec![0u8; head.data_len as usize];
    if head.data_len > 0 {
        let r = conn.read_exact(&mut body_buf).await;
        if let Err(e) = r {
            error!("read body failed, err: {}", e);
        } else {
            body = Some(String::from_utf8_lossy(&body_buf));
            debug!("sync text received: {}", body.as_ref().unwrap());
        }
    }

    if let Some(body) = &body {
        // If the clipboard content is the same as the current content, do not set it to avoid triggering the clipboard change event
        let cur_text = crate::config::CLIPBOARD.read_text().unwrap_or_default();
        if cur_text != *body
            && let Err(e) = crate::config::CLIPBOARD.write_text(body.to_string())
        {
            let msg = format!("set clipboard text failed, err: {e}");
            error!("{}", msg);
            let _ = resp_common_error_msg(conn, &msg).await;
            return true;
        }
    }

    send_clipboard_response(conn).await
}

/// Sends clipboard content (image if available, otherwise text)
async fn send_clipboard_response(conn: &mut TlsStream<TcpStream>) -> bool {
    // Try to send clipboard image first, if available
    if let Some(image_data) = try_get_clipboard_image_png() {
        let image_name = chrono::Local::now().format("%Y%m%d%H%M%S").to_string() + ".png";

        // Save sent image to local file
        if let Err(e) = save_image_to_file(&image_data, "sent").await {
            warn!("save sent clipboard image to file failed, err: {}", e);
        }

        return send_msg_with_body(conn, &image_name, RouteDataType::ClipImage, &image_data)
            .await
            .is_ok();
    }

    // Fallback to text
    let cur_clipboard_text = crate::config::CLIPBOARD.read_text().unwrap_or_default();
    send_msg_with_body(
        conn,
        &"".to_string(),
        RouteDataType::Text,
        cur_clipboard_text.as_ref(),
    )
    .await
    .is_ok()
}

/// Handles receiving clipboard image from client and sends back current clipboard content
async fn sync_clipboard_image_handler(
    conn: &mut TlsStream<TcpStream>,
    head: &RouteRecvHead,
) -> bool {
    let mut body_buf = vec![0u8; head.data_len as usize];
    if head.data_len > 0 {
        if let Err(e) = conn.read_exact(&mut body_buf).await {
            error!("read clipboard image body failed, err: {}", e);
            return false;
        }
        debug!(
            "sync clipboard image received, size: {} bytes",
            body_buf.len()
        );

        // Save received image to local file
        if let Err(e) = save_image_to_file(&body_buf, "received").await {
            warn!("save received clipboard image to file failed, err: {}", e);
        }

        // Write image to clipboard
        if let Err(e) = crate::config::CLIPBOARD.write_image_from_bytes(&body_buf) {
            let msg = format!("set clipboard image failed, err: {e}");
            error!("{}", msg);
            let _ = resp_common_error_msg(conn, &msg).await;
            return true;
        }
    }

    send_clipboard_response(conn).await
}

/// Handles sync file operation info (similar to paste_file_operation_handler but without sending response)
async fn sync_file_operation_handler(
    conn: &mut TlsStream<TcpStream>,
    head: &RouteRecvHead,
) -> bool {
    let mut data_buf = vec![0u8; head.data_len as usize];
    if let Err(e) = conn.read_exact(&mut data_buf).await {
        error!("read body failed, err: {}", e);
        return false;
    }
    let op_info: crate::route::protocol::UploadOperationInfo =
        match serde_json::from_slice(&data_buf) {
            Ok(info) => info,
            Err(e) => {
                error!("parse upload operation info failed, err: {}", e);
                return false;
            }
        };
    info!(
        "sync file operation, total size: {}, total count: {}",
        op_info.files_size_in_this_op, op_info.files_count_in_this_op
    );
    debug!("sync file operation info: {:?}", op_info);

    if let Err(e) = crate::file::GLOBAL_RECEIVER_SESSION_MANAGER
        .create_op_info(head, &op_info)
        .await
    {
        error!("create op info failed, err: {}", e);
        let _ = resp_common_error_msg(conn, &e).await;
        return false;
    };

    let save_path = crate::config::GLOBAL_CONFIG
        .read()
        .unwrap()
        .save_path
        .clone();
    let download_dir = std::path::PathBuf::from(&save_path);

    use crate::utils::NormalizePath;
    if let Some(empty_dir) = &op_info.empty_dirs {
        for dir in empty_dir {
            let dir = dir.normalize_path();
            let r = tokio::fs::create_dir_all(download_dir.join(dir)).await;
            if let Err(err) = r {
                error!("create dir error: {}", err);
                let _ = resp_common_error_msg(conn, &err.to_string()).await;
                return false;
            }
        }
    }

    if op_info.empty_dirs.is_some() && op_info.files_count_in_this_op == 0 {
        crate::utils::inform(
            LanguageKey::DirCreatedSuccessfully.translate(),
            &head.device_name,
            Some(&save_path),
        );
    }
    true
}

/// Saves image data to a file in the configured save path
async fn save_image_to_file(image_data: &[u8], prefix: &str) -> Result<String, String> {
    let save_path = crate::config::GLOBAL_CONFIG
        .read()
        .unwrap()
        .save_path
        .clone();

    let file_name = format!(
        "{}_{}.png",
        prefix,
        chrono::Local::now().format("%Y%m%d%H%M%S%3f")
    );
    let file_path = std::path::PathBuf::from(&save_path).join(&file_name);

    if let Err(e) = tokio::fs::create_dir_all(&save_path).await {
        return Err(format!("create save directory failed: {e}"));
    }

    if let Err(e) = tokio::fs::write(&file_path, image_data).await {
        return Err(format!("write image file failed: {e}"));
    }

    let path_str = file_path.to_string_lossy().to_string();
    info!("clipboard image saved to: {}", path_str);
    Ok(path_str)
}

fn try_get_clipboard_image_png() -> Option<Vec<u8>> {
    use clipboard_rs::common::RustImage;

    let raw_image = match crate::config::CLIPBOARD.read_image() {
        Ok(img) => img,
        Err(_) => return None,
    };

    let dyn_img: image::DynamicImage;
    let mut cursor_buf: std::io::Cursor<Vec<u8>>;

    if let Some(image1) = raw_image.image1 {
        let img_buf = image::ImageBuffer::from_vec(
            image1.width as u32,
            image1.height as u32,
            image1.bytes.into_owned(),
        )?;
        cursor_buf = std::io::Cursor::new(Vec::with_capacity(img_buf.len() * 4));
        dyn_img = image::DynamicImage::ImageRgba8(img_buf);
    } else if let Some(image2) = raw_image.image2 {
        dyn_img = image2.get_dynamic_image().ok()?;
        cursor_buf = std::io::Cursor::new(Vec::with_capacity(1024 * 100));
    } else {
        return None;
    }

    dyn_img
        .write_to(&mut cursor_buf, image::ImageFormat::Png)
        .ok()?;
    Some(cursor_buf.into_inner())
}

/// return whether should continue loop(like no socket error)
pub async fn paste_file_handler(conn: &mut TlsStream<TcpStream>, head: RouteRecvHead) -> bool {
    if let crate::route::protocol::UploadType::UploadInfo = head.upload_type {
        return paste_file_operation_handler(conn, head).await;
    }

    // head.End == 0 && head.Start == 0 means the file is empty
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
        return resp_common_error_msg(conn, &format!("create file error: {err}"))
            .await
            .is_ok();
    }
    let file = file.unwrap();
    let file_writer =
        crate::file::FilePartWriter::new(file, head.start as usize, head.end as usize).await;
    if let Err(err) = file_writer {
        error!("new file writer failed, err: {}", err);
        return resp_common_error_msg(conn, &format!("new file writer failed, err: {err}"))
            .await
            .is_ok();
    }
    let mut file_writer = file_writer.unwrap();

    let progress_handle = match crate::file::GLOBAL_RECEIVER_SESSION_MANAGER
        .get_op_progress_handle(head.op_id)
        .await
    {
        Some(handle) => handle,
        None => return false, // this operation had been terminated
    };

    file_writer = file_writer.set_on_pull_write_ok(move |data: &[u8]| {
        if !data.is_empty() {
            use std::sync::atomic::Ordering::Relaxed;
            progress_handle
                .current_pos
                .fetch_add(data.len() as u64, Relaxed);
        }
    });

    let (conn_reader, mut conn_writer) = tokio::io::split(conn);

    const MIN_WRITE_BUF_SIZE: i64 = 4 * 1024 * 1024;
    const MAX_WRITE_BUF_SIZE: i64 = 8 * 1024 * 1024;
    const PART_SIZE: i64 = 4096;
    // Divide by 8 to estimate a reasonable buffer size
    let mut write_buf_size: i64 = std::cmp::max(data_len / 8, MIN_WRITE_BUF_SIZE);
    // Round down to nearest multiple of PART_SIZE
    write_buf_size /= PART_SIZE;
    write_buf_size *= PART_SIZE;
    if data_len < MIN_WRITE_BUF_SIZE {
        write_buf_size = data_len;
    } else if write_buf_size > MAX_WRITE_BUF_SIZE {
        write_buf_size = MAX_WRITE_BUF_SIZE;
    }

    // Testing large file upload in 10 chunks
    // 8192 KB read buffer, 2M ~ 4M write buffer: fastest speed 80 MB/s
    // 8192 KB read buffer, 7M write buffer: slightly slower speed 89 MB/s
    // 8192 KB read buffer, 0M write buffer: slightly slower speed 50 MB/s
    // 7M read buffer, 0M write buffer: very slow speed 18 MB/s

    // let mut conn_buf_reader =
    //     tokio::io::BufReader::with_capacity(copy_buffer_size, conn_reader.take(data_len as u64));
    let mut file_buf_writer =
        tokio::io::BufWriter::with_capacity(write_buf_size as usize, &mut file_writer);

    let n = tokio::io::copy(&mut conn_reader.take(data_len as u64), &mut file_buf_writer).await;
    // let n = tokio::io::copy_buf(&mut conn_buf_reader, &mut file_buf_writer).await;
    if let Err(err) = n {
        let msg = format!("write file error: {err}");
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
            &format!("flush file writer failed, err: {err}"),
        )
        .await
        .is_ok();
    }
    if n < data_len as u64 {
        let msg = format!("write file error, n: {n}, dataLen: {data_len}");
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
    let op_info: crate::route::protocol::UploadOperationInfo =
        match serde_json::from_slice(&data_buf) {
            Ok(info) => info,
            Err(e) => {
                error!("parse upload operation info failed, err: {}", e);
                return false;
            }
        };
    info!(
        "paste file operation, total size: {}, total count: {}",
        op_info.files_size_in_this_op, op_info.files_count_in_this_op
    );
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
