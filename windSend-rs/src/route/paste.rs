use crate::route::resp::{resp_error_msg, send_msg, send_msg_with_body};
use crate::route::{RouteDataType, RouteHead};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio_rustls::server::TlsStream;
use tracing::{debug, error, info, trace, warn};

pub async fn ping_handler(conn: &mut TlsStream<TcpStream>, head: RouteHead) -> Result<(), ()> {
    let mut body_buf = vec![0u8; head.data_len as usize];
    conn.read_exact(&mut body_buf)
        .await
        .map_err(|e| error!("read body failed, err: {}", e))?;
    let decrypted_body = crate::config::get_cryptor()
        .map_err(|e| error!("get_cryptor failed, err: {}", e))?
        .decrypt(&body_buf)
        .map_err(|e| error!("decrypt failed, err: {}", e))?;
    if decrypted_body != b"ping" {
        error!(
            "invalid ping data: {}",
            String::from_utf8_lossy(&decrypted_body)
        );
        resp_error_msg(conn, &format!("invalid ping data: {:?}", decrypted_body))
            .await
            .ok();
        return Err(());
    }
    let resp = b"pong";
    let encrypted_resp = crate::config::get_cryptor()
        .map_err(|e| error!("get_cryptor failed, err: {}", e))?
        .encrypt(resp)
        .map_err(|e| error!("encrypt failed, err: {}", e))?;
    send_msg_with_body(
        conn,
        &"验证成功".to_string(),
        RouteDataType::Text,
        &encrypted_resp,
    )
    .await?;
    Err(())
}

pub async fn paste_text_handler(conn: &mut TlsStream<TcpStream>, head: RouteHead) {
    let mut body_buf = vec![0u8; head.data_len as usize];
    conn.read_exact(&mut body_buf)
        .await
        .map_err(|e| error!("read body failed, err: {}", e))
        .ok();
    let body = String::from_utf8_lossy(&body_buf);
    debug!("paste text data: {}", body);
    {
        let clipboard = &mut crate::config::CLIPBOARD.lock().unwrap();
        clipboard
            .set_text(body.clone())
            .map_err(|e| error!("set clipboard text failed, err: {}", e))
            .ok();
    }
    crate::utils::inform(&body);
    send_msg(conn, &"粘贴成功".to_string()).await.ok();
}

pub async fn paste_file_handler(mut conn: TlsStream<TcpStream>, head: RouteHead) {
    // head.End == 0 && head.Start == 0 表示文件为空
    if head.end <= head.start && !(head.end == 0 && head.start == 0) {
        let err_msg = &format!("invalid file part, start:{}, end:{}", head.start, head.end);
        error!("{}", err_msg);
        resp_error_msg(&mut conn, err_msg).await.ok();
        return;
    }
    let data_len = head.end - head.start;
    if head.data_len != data_len {
        let err_msg = &format!(
            "invalid file part, dataLen:{}, start:{}, end:{}",
            head.data_len, head.start, head.end
        );
        error!("{}", err_msg);
        resp_error_msg(&mut conn, err_msg).await.ok();
        return;
    }
    if head.files_count_in_this_op == 0 {
        let err_msg = &format!(
            "invalid file part, FilesCountInThisOp:{}",
            head.files_count_in_this_op
        );
        error!("{}", err_msg);
        resp_error_msg(&mut conn, err_msg).await.ok();
        return;
    }
    // let file = (*crate::file::GLOBAL_FILE_RECEIVER).clone().borrow_mut();
    let file = crate::file::GLOBAL_FILE_RECEIVER.get_file(&head).await;
    if file.is_err() {
        let err = file.err().unwrap();
        error!("create file error: {}", err);
        resp_error_msg(&mut conn, &format!("create file error: {}", err))
            .await
            .ok();
        return;
    }
    trace!("file: {:?}", file);
    let file = file.unwrap();
    let file_writer =
        crate::file::FilePartWriter::new(file, head.start as usize, head.end as usize).await;
    if file_writer.is_err() {
        let err = file_writer.err().unwrap();
        error!("new file writer failed, err: {}", err);
        resp_error_msg(&mut conn, &format!("new file writer failed, err: {}", err))
            .await
            .ok();
        return;
    }
    let mut file_writer = file_writer.unwrap();
    // 8 is a magic number
    let buf_size = std::cmp::max((data_len / 8) as usize, 4096);
    println!("buf_size: {}", buf_size);
    let (conn_reader, mut conn_writer) = tokio::io::split(conn);
    // let mut reader =
    //     tokio::io::BufReader::with_capacity(buf_size, conn_reader.take(data_len as u64));
    let mut buf_writer = tokio::io::BufWriter::with_capacity(buf_size, &mut file_writer);
    // rust需要写缓冲速度才会上来，go读缓冲速度最快。
    // rust只开启读缓冲或同时开启写缓冲和读缓冲速度都很慢。
    let n = tokio::io::copy(&mut conn_reader.take(data_len as u64), &mut buf_writer).await;
    // let n = tokio::io::copy(&mut reader, &mut file_writer).await;
    if buf_writer.flush().await.is_err() {
        let err = n.err().unwrap();
        error!("flush file writer failed, err: {}", err);
        resp_error_msg(
            &mut conn_writer,
            &format!("flush file writer failed, err: {}", err),
        )
        .await
        .ok();
        return;
    }
    if n.is_err() {
        let err = n.err().unwrap();
        let msg = format!("write file error: {}", err);
        error!("{}", msg);
        resp_error_msg(&mut conn_writer, &msg).await.ok();
        crate::file::GLOBAL_FILE_RECEIVER
            .report_file_part(head.file_id, head.start, head.end, Some(msg))
            .await;
        return;
    }
    let n = n.unwrap();
    if n < data_len as u64 {
        let msg = format!("write file error, n: {}, dataLen: {}", n, data_len);
        error!("{}", msg);
        resp_error_msg(&mut conn_writer, &msg).await.ok();
        crate::file::GLOBAL_FILE_RECEIVER
            .report_file_part(head.file_id, head.start, head.end, Some(msg))
            .await;
        return;
    }
    if n > data_len as u64 {
        // should not happen
        warn!("write file error, n: {}, dataLen: {}", n, data_len);
    }
    // part written successfully
    send_msg(
        &mut conn_writer,
        &format!(
            "file part written successfully, fileID:{}, start:{}, end:{}",
            head.file_id, head.start, head.end
        ),
    )
    .await
    .ok();
    debug!(
        "write file success, fileID: {}, start: {}, end: {}",
        head.file_id, head.start, head.end
    );
    let (done, err_occurred) = crate::file::GLOBAL_FILE_RECEIVER
        .report_file_part(head.file_id, head.start, head.end, None)
        .await;
    if err_occurred {
        return;
    }
    if done {
        info!("save file success: {}", head.file_name);
    }
}
