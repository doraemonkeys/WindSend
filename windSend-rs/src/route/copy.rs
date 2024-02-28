use crate::language::{LanguageKey, LANGUAGE_MANAGER};
use crate::route::resp::{resp_common_error_msg, send_head, send_msg_with_body};
use crate::route::{RouteDataType, RoutePathInfo, RouteRecvHead, RouteRespHead};
use std::path::PathBuf;
use tokio::net::TcpStream;
use tokio_rustls::server::TlsStream;
use tracing::{debug, error, warn};

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
        if let Ok(_) = r {
            #[cfg(not(feature = "disable-systray-support"))]
            crate::TX_RESET_FILES_ITEM
                .get()
                .unwrap()
                .try_send(())
                .unwrap();
        }
        *crate::SELECTED_FILES.get().unwrap().lock().unwrap() = std::collections::HashSet::new();
        return;
    }

    // 文件剪切板
    #[cfg(not(target_os = "linux"))]
    match clipboard_files::read() {
        Ok(files) => {
            let files = files.into_iter().map(|f| f.display().to_string());
            let r = send_files(conn, files).await;
            if r.is_ok() {
                let r = crate::config::CLIPBOARD.lock().unwrap().clear();
                if let Err(e) = r {
                    error!("clear clipboard failed, err: {}", e);
                }
                return;
            }
        }
        Err(e) => debug!("clipboard_files::read failed, err: {:?}", e),
    }

    {
        let r1 = send_text(conn).await;
        if !r1.is_err() {
            return;
        }
        let r2 = send_image(conn).await;
        if !r2.is_err() {
            return;
        }
        if let Err(e) = r1 {
            warn!("send text failed, err: {}", e);
        }
        if let Err(e) = r2 {
            warn!("send image failed, err: {}", e);
        }
    }
    let clipboard_is_empty = LANGUAGE_MANAGER
        .read()
        .unwrap()
        .translate(LanguageKey::ClipboardIsEmpty);
    let _ = resp_common_error_msg(conn, clipboard_is_empty).await;
}

#[allow(dead_code)]
async fn send_files<T: IntoIterator<Item = String>>(
    conn: &mut TlsStream<TcpStream>,
    paths: T,
) -> Result<(), ()> {
    let mut resp_paths = Vec::<RoutePathInfo>::new();
    for path1 in paths {
        let path_attr = tokio::fs::metadata(&path1).await;
        let path_attr = match path_attr {
            Ok(attr) => attr,
            Err(err) => {
                error!("get file attr failed, err: {}", err);
                continue;
            }
        };
        let mut rpi: RoutePathInfo = RoutePathInfo::default();
        rpi.path = path1.clone();
        if path_attr.is_file() {
            rpi.type_ = crate::route::PathInfoType::File;
            rpi.size = path_attr.len();
            resp_paths.push(rpi);
            continue;
        }
        rpi.type_ = crate::route::PathInfoType::Dir;
        let dir_root = std::path::Path::new(&path1)
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string();
        rpi.save_path = dir_root.clone();
        resp_paths.push(rpi);

        static DEFAULT_SEPARATOR: &str = "/";
        static REVERSE_SEPARATOR: &str = "\\";
        let path1 = path1.replace(REVERSE_SEPARATOR, DEFAULT_SEPARATOR);
        for entry in walkdir::WalkDir::new(&path1) {
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
            let mut rpi: RoutePathInfo = RoutePathInfo::default();
            rpi.path = path2.clone();
            rpi.type_ = if entry.file_type().is_dir() {
                crate::route::PathInfoType::Dir
            } else {
                crate::route::PathInfoType::File
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
            if let crate::route::PathInfoType::File = rpi.type_ {
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
    let copy_successfully = LANGUAGE_MANAGER
        .read()
        .unwrap()
        .translate(LanguageKey::CopySuccessfully);
    let body = match serde_json::to_vec(&resp_paths) {
        Ok(body) => body,
        Err(err) => {
            let msg = format!("serde_json::to_vec failed, err: {}", err);
            error!("{}", &msg);
            let _ = resp_common_error_msg(conn, &msg).await;
            return Err(());
        }
    };
    send_msg_with_body(conn, copy_successfully, RouteDataType::Files, &body).await
}

async fn send_image(conn: &mut TlsStream<TcpStream>) -> Result<(), Box<dyn std::error::Error>> {
    let image_name = chrono::Local::now().format("%Y%m%d%H%M%S").to_string() + ".png";
    let raw_image = crate::config::CLIPBOARD.lock().unwrap().get_image();
    if let Err(err) = raw_image {
        let info = format!("{}", err);
        return Err(info.into());
    }
    let raw_image = raw_image.unwrap();
    let img_buf = image::ImageBuffer::from_vec(
        raw_image.width as u32,
        raw_image.height as u32,
        raw_image.bytes.into_owned(),
    )
    .ok_or("image::ImageBuffer::from_vec failed")?;
    let mut cursor_buf = std::io::Cursor::new(Vec::with_capacity(img_buf.len() * 4));
    let img_buf = image::DynamicImage::ImageRgba8(img_buf);
    img_buf.write_to(&mut cursor_buf, image::ImageOutputFormat::Png)?;
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

async fn send_text(conn: &mut TlsStream<TcpStream>) -> Result<(), String> {
    let data_text = crate::config::CLIPBOARD.lock().unwrap().get_text();
    if let Err(e) = data_text {
        let info = format!("{}", e);
        return Err(info);
    }
    let data_text = data_text.unwrap();
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

/// 返回是否应该继续循环(比如没有遇到Socket Error)
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
