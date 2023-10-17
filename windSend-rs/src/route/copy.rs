use crate::route::resp::{resp_error_msg, send_head, send_msg_with_body};
use crate::route::{RouteDataType, RouteHead, RoutePathInfo, RouteRespHead};
use std::ops::ControlFlow;
use tokio::net::TcpStream;
use tokio_rustls::server::TlsStream;
use tracing::{debug, error, warn};

pub async fn copy_handler(conn: &mut TlsStream<TcpStream>) {
    if let ControlFlow::Break(_) = send_files(conn).await {
        return;
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
        if r1.is_err() {
            let err = r1.err().unwrap();
            error!("send text failed, err: {}", err);
        }
        if r2.is_err() {
            let err = r2.err().unwrap();
            error!("send image failed, err: {}", err);
        }
    }
    resp_error_msg(conn, &"你还没有复制任何内容".to_string())
        .await
        .ok();
}

async fn send_files(conn: &mut TlsStream<TcpStream>) -> ControlFlow<()> {
    let mut selected_paths;
    {
        let mut files = crate::systray::SELECTED_FILES
            .get()
            .unwrap()
            .lock()
            .unwrap();
        if files.is_empty() {
            return ControlFlow::Continue(());
        }
        selected_paths = Vec::<RoutePathInfo>::with_capacity(files.len());
        for file in files.drain() {
            let path = file;
            let size = std::fs::metadata(&path).map(|m| m.len());
            if size.is_err() {
                error!("get file size failed, err: {}", size.err().unwrap());
                continue;
            }
            let size = size.unwrap();
            selected_paths.push(RoutePathInfo { path, size });
        }
    }
    let resp = RouteRespHead {
        code: crate::route::resp::SUCCESS_STATUS_CODE,
        msg: &"复制成功".to_string(),
        data_type: RouteDataType::Files,
        data_len: 0,
        paths: selected_paths,
    };
    if send_head(conn, &resp).await.is_ok() {
        crate::RX_RESET_FILES_ITEM.get().unwrap().send(()).unwrap();
    }
    return ControlFlow::Break(());
}

async fn send_image(conn: &mut TlsStream<TcpStream>) -> Result<(), Box<dyn std::error::Error>> {
    let image_name = chrono::Local::now().format("%Y%m%d%H%M%S").to_string() + ".png";
    let raw_image = crate::config::CLIPBOARD.lock().unwrap().get_image();
    if raw_image.is_err() {
        let data = raw_image.err().unwrap();
        let info = format!("{}", data);
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
    if data_text.is_err() {
        let data_text = data_text.err().unwrap();
        let info = format!("{}", data_text);
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
pub async fn download_handler(conn: &mut TlsStream<TcpStream>, head: RouteHead) {
    // 检查文件是否存在
    if !std::path::Path::new(&head.down_path).exists() {
        error!("file not exists: {}", head.down_path);
        resp_error_msg(conn, &format!("file not exists: {}", head.down_path))
            .await
            .ok();
        return;
    }
    debug!(
        "downloading file {} from {} to {}",
        head.down_path, head.start, head.end
    );
    let file = tokio::fs::File::open(&head.down_path).await;
    if file.is_err() {
        let err = file.err().unwrap();
        error!("open file failed, err: {}", err);
        resp_error_msg(conn, &format!("open file failed, err: {}", err))
            .await
            .ok();
        return;
    }
    let resp = RouteRespHead {
        code: crate::route::resp::SUCCESS_STATUS_CODE,
        msg: &"start download".to_string(),
        data_type: RouteDataType::Binary,
        data_len: head.end - head.start,
        paths: vec![],
    };
    if send_head(conn, &resp).await.is_err() {
        return;
    }
    let file = file.unwrap();
    let file_reader =
        crate::file::FilePartReader::new(file, head.start as usize, head.end as usize).await;
    if file_reader.is_err() {
        let err = file_reader.err().unwrap();
        error!("new file part reader failed, err: {}", err);
        return;
    }
    static MAX_BUF_SIZE: usize = 1024 * 1024 * 30;
    let file_reader = file_reader.unwrap();
    let buf_size = std::cmp::min((head.end - head.start) as usize, MAX_BUF_SIZE);
    let mut file_part_reader = tokio::io::BufReader::with_capacity(buf_size, file_reader);
    let n = tokio::io::copy(&mut file_part_reader, conn).await;
    if n.is_err() {
        let err = n.err().unwrap();
        error!("copy file to conn failed, err: {}", err);
        return;
    }
    let n = n.unwrap() as i64;
    if n != head.end - head.start {
        warn!(
            "copy file to conn failed, n != expectedSize, n: {}, expectedSize: {}",
            n,
            head.end - head.start
        );
    }
}
