use crate::language::{LanguageKey, LANGUAGE_MANAGER};
use crate::route::resp::{resp_common_error_msg, send_head, send_msg_with_body};
use crate::route::{RouteDataType, RouteRecvHead, RouteRespHead, RouteTransferInfo};
use std::path::PathBuf;
use tokio::net::TcpStream;
use tokio_rustls::server::TlsStream;
use tracing::{debug, error, info, warn};

pub async fn copy_handler(conn: &mut TlsStream<TcpStream>) {
    // 用户选择的文件
    let selected_files = crate::SELECTED_FILES.get();
    let files = match selected_files {
        Some(selected) => {
            let selected = selected.lock().unwrap();
            match selected.is_empty() {
                true => None,
                false => Some(selected.clone()),
            }
        }
        None => None,
    };
    if let Some(files) = files {
        let r = send_files(conn, files).await;
        if r.is_ok() {
            #[cfg(not(feature = "disable-systray-support"))]
            crate::TX_RESET_FILES.get().unwrap().try_send(()).unwrap();
        }
        *crate::SELECTED_FILES.get().unwrap().lock().unwrap() = std::collections::HashSet::new();
        return;
    }

    // 文件剪切板(在读文本剪切板之前查看，文件地址可能会被当做文本读取到)
    match crate::config::CLIPBOARD.get_files() {
        Ok(files) => {
            if !files.is_empty() && send_files(conn, files).await.is_ok() {
                if let Err(e) = crate::config::CLIPBOARD.clear() {
                    error!("clear clipboard failed, err: {}", e);
                }
            }
        }
        Err(e) => debug!("get clipboard files failed, err: {}", e),
    }

    {
        match send_clipboard_text(conn).await {
            Ok(_) => return,
            Err(e) => info!("send text failed, err: {}", e),
        }
        match send_clipboard_image(conn).await {
            Ok(_) => return,
            Err(e) => info!("send image failed, err: {}", e),
        }
    }

    let clipboard_is_empty = LANGUAGE_MANAGER
        .read()
        .unwrap()
        .translate(LanguageKey::ClipboardIsEmpty);
    let _ = resp_common_error_msg(conn, clipboard_is_empty).await;
}

#[allow(dead_code)]
async fn send_files<T: IntoIterator<Item = String> + std::fmt::Debug>(
    conn: &mut TlsStream<TcpStream>,
    paths: T,
) -> Result<(), ()> {
    debug!("send_files: {:?}", &paths);
    let mut resp_paths = Vec::<RouteTransferInfo>::new();
    for path1 in paths {
        let path_attr = tokio::fs::metadata(&path1).await;
        let path_attr = match path_attr {
            Ok(attr) => attr,
            Err(err) => {
                error!("get [{}] attr failed, err: {}", &path1, err);
                continue;
            }
        };
        let mut rpi: RouteTransferInfo = RouteTransferInfo {
            remote_path: path1.clone(),
            ..Default::default()
        };
        if path_attr.is_file() {
            rpi.type_ = crate::route::PathType::File;
            rpi.size = path_attr.len();
            resp_paths.push(rpi);
            continue;
        } else {
            rpi.type_ = crate::route::PathType::Dir;
        }
        resp_paths.push(rpi);

        let dir_root = std::path::Path::new(&path1)
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string();
        static DEFAULT_SEPARATOR: &str = "/";
        static REVERSE_SEPARATOR: &str = "\\";
        let path1 = path1.replace(REVERSE_SEPARATOR, DEFAULT_SEPARATOR);
        let mut is_root_dir = true;
        for entry in walkdir::WalkDir::new(&path1) {
            if is_root_dir {
                // skip root dir
                is_root_dir = false;
                continue;
            }
            let entry = match entry {
                Ok(entry) => entry,
                Err(err) => {
                    error!("walkdir entry failed, err: {}", err);
                    continue;
                }
            };
            let path2 = entry
                .path()
                .display()
                .to_string()
                .replace(REVERSE_SEPARATOR, DEFAULT_SEPARATOR);
            let mut rpi = RouteTransferInfo {
                remote_path: path2.clone(),
                type_: if entry.file_type().is_dir() {
                    crate::route::PathType::Dir
                } else {
                    crate::route::PathType::File
                },
                ..Default::default()
            };
            // dbg!(&dir_root);
            // dbg!(&path1, &path2);
            // dbg!(path2.strip_prefix(&path1).unwrap_or_default());
            let relative_path = path2
                .strip_prefix(&path1)
                .unwrap_or_default()
                .trim_start_matches(DEFAULT_SEPARATOR);
            rpi.save_path = PathBuf::from(dir_root.clone())
                .join(relative_path)
                .to_string_lossy()
                .to_string();
            if let crate::route::PathType::File = rpi.type_ {
                rpi.size = entry.metadata().unwrap().len();
                rpi.save_path = PathBuf::from(rpi.save_path)
                    .parent()
                    .unwrap()
                    .to_string_lossy()
                    .to_string();
            }
            // println!("{:?}", &rpi.save_path);
            resp_paths.push(rpi);
        }
    }
    // dbg!(&resp_paths);
    if resp_paths.is_empty() {
        let msg = "send_files unexpected empty paths";
        error!("{}", msg);
        resp_common_error_msg(conn, &msg.to_string()).await.ok();
        return Err(());
    }
    debug!("{:?}", &resp_paths);
    let body = match serde_json::to_vec(&resp_paths) {
        Ok(body) => body,
        Err(err) => {
            let msg = format!("serde_json::to_vec failed, err: {}", err);
            error!("{}", &msg);
            let _ = resp_common_error_msg(conn, &msg).await;
            return Err(());
        }
    };
    send_msg_with_body(
        conn,
        LanguageKey::CopySuccessfully.translate(),
        RouteDataType::Files,
        &body,
    )
    .await
}

async fn send_clipboard_image(
    conn: &mut TlsStream<TcpStream>,
) -> Result<(), Box<dyn std::error::Error>> {
    let image_name = chrono::Local::now().format("%Y%m%d%H%M%S").to_string() + ".png";
    let raw_image = match crate::config::CLIPBOARD.read_image() {
        Ok(raw_image) => raw_image,
        Err(err) => return Err(format!("read clipboard image failed, err: {}", err).into()),
    };
    let dyn_img: image::DynamicImage;
    let mut cursor_buf: std::io::Cursor<Vec<u8>>;
    if let Some(image1) = raw_image.image1 {
        let img_buf = image::ImageBuffer::from_vec(
            image1.width as u32,
            image1.height as u32,
            image1.bytes.into_owned(),
        )
        .ok_or("image::ImageBuffer::from_vec failed")?;
        cursor_buf = std::io::Cursor::new(Vec::with_capacity(img_buf.len() * 4));
        dyn_img = image::DynamicImage::ImageRgba8(img_buf);
    } else if let Some(image2) = raw_image.image2 {
        use clipboard_rs::common::RustImage;
        dyn_img = match image2.get_dynamic_image() {
            Ok(img) => img,
            Err(err) => return Err(format!("image2.get_dynamic_image failed, err: {}", err).into()),
        };
        cursor_buf = std::io::Cursor::new(Vec::with_capacity(1024 * 100));
    } else {
        return Err("no image in clipboard".into());
    }
    dyn_img.write_to(&mut cursor_buf, image::ImageFormat::Png)?;
    send_msg_with_body(
        conn,
        &image_name,
        RouteDataType::ClipImage,
        &cursor_buf.into_inner(),
    )
    .await
    .ok();
    Ok(())
}

async fn send_clipboard_text(conn: &mut TlsStream<TcpStream>) -> Result<(), String> {
    let data_text = match crate::config::CLIPBOARD.read_text() {
        Ok(data_text) => data_text,
        Err(err) => return Err(format!("read clipboard text failed, err: {}", err)),
    };
    send_msg_with_body(
        conn,
        &"".to_string(),
        RouteDataType::Text,
        data_text.as_bytes(),
    )
    .await
    .ok();
    Ok(())
}

/// This function returns whether to continue the loop (for example, not encountering a Socket Error)
pub async fn download_handler(conn: &mut TlsStream<TcpStream>, head: RouteRecvHead) -> bool {
    // 检查文件是否存在
    if !std::path::Path::new(&head.path).exists() {
        error!("file not exists: {}", head.path);
        let r = resp_common_error_msg(conn, &format!("file not exists: {}", head.path)).await;
        return r.is_ok();
    }
    debug!(
        "downloading file {} from {} to {}",
        head.path, head.start, head.end
    );
    let file = tokio::fs::File::open(&head.path).await;
    if let Err(err) = file {
        error!("open file failed, err: {}", err);
        let r = resp_common_error_msg(conn, &format!("open file failed, err: {}", err)).await;
        return r.is_ok();
    }
    let resp = RouteRespHead {
        code: crate::route::resp::SUCCESS_STATUS_CODE,
        msg: &"start download".to_string(),
        data_type: RouteDataType::Binary,
        data_len: head.end - head.start,
    };
    if send_head(conn, &resp).await.is_err() {
        return false;
    }
    let file = file.unwrap();
    let file_reader =
        crate::file::FilePartReader::new(file, head.start as usize, head.end as usize).await;
    if let Err(err) = file_reader {
        error!("new file part reader failed, err: {}", err);
        return false;
    }
    const MAX_BUF_SIZE: usize = 1024 * 1024 * 30;
    let file_reader = file_reader.unwrap();
    let buf_size = std::cmp::min((head.end - head.start) as usize, MAX_BUF_SIZE);
    let mut file_part_reader = tokio::io::BufReader::with_capacity(buf_size, file_reader);
    let n = tokio::io::copy(&mut file_part_reader, conn).await;
    if let Err(err) = n {
        error!("copy file to conn failed, err: {}", err);
        return false;
    }
    let n = n.unwrap() as i64;
    if n != head.end - head.start {
        warn!(
            "copy file to conn failed, n != expectedSize, n: {}, expectedSize: {}",
            n,
            head.end - head.start
        );
    }
    true
}
