use std::collections::HashMap;
use std::io::SeekFrom;
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncSeekExt, Take};
use tokio::sync::Mutex as TokioMutex;
use tracing::{debug, error, warn};
pub struct FilePartReader {
    file_part: Take<tokio::fs::File>,
}

impl FilePartReader {
    /// file句柄不能在其他地方同时读取,否则seek游标会出错。
    pub async fn new(mut file: tokio::fs::File, start: usize, end: usize) -> std::io::Result<Self> {
        file.seek(SeekFrom::Start(start as u64)).await?;
        let part = file.take((end - start) as u64);
        Ok(Self { file_part: part })
    }
}

impl tokio::io::AsyncRead for FilePartReader {
    fn poll_read(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        buf: &mut tokio::io::ReadBuf<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        std::pin::Pin::new(&mut self.file_part).poll_read(cx, buf)
    }
}

pub struct FilePartWriter {
    file_part: tokio::fs::File,
    pos: usize,
    end: usize,
}

impl FilePartWriter {
    /// file句柄不能在其他地方同时写入,否则seek游标会出错。
    pub async fn new(mut file: tokio::fs::File, start: usize, end: usize) -> std::io::Result<Self> {
        file.seek(SeekFrom::Start(start as u64)).await?;
        Ok(Self {
            file_part: file,
            pos: start,
            end,
        })
    }
}

impl tokio::io::AsyncWrite for FilePartWriter {
    fn poll_write(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        buf: &[u8],
    ) -> std::task::Poll<std::io::Result<usize>> {
        let buf_len = buf.len();
        let new_buf;
        if buf_len + self.pos > self.end {
            warn!(
                "write file error,buf len: {}, pos: {}, end: {}",
                buf_len, self.pos, self.end
            );
            self.pos = self.end;
            new_buf = &buf[..self.end - self.pos];
        } else {
            new_buf = buf;
        }
        let poll = std::pin::Pin::new(&mut self.file_part).poll_write(cx, new_buf);
        if let std::task::Poll::Ready(Ok(n)) = poll {
            self.pos += n;
        }
        poll
    }

    fn poll_flush(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        std::pin::Pin::new(&mut self.file_part).poll_flush(cx)
    }

    fn poll_shutdown(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        std::pin::Pin::new(&mut self.file_part).poll_shutdown(cx)
    }
}

pub struct FileReceiver {
    file: Arc<TokioMutex<HashMap<u32, RecvFileInfo>>>,
    ops: Arc<TokioMutex<HashMap<u32, OpInfo>>>,
}

#[derive(Debug, Clone)]
pub struct OpInfo {
    exp_num: i32,
    succ_num: i32,
    fail_num: i32,
}

#[derive(Debug)]
pub struct RecvFileInfo {
    exp_size: i64,
    /// fileID在每次传输一个文件时都是随机的，
    /// 即使再次传输同一个文件，也会重新生成一个fileID
    _file_id: u32,
    /// 保护part、is_done、first_err、down_chan
    part_lock: TokioMutex<()>,
    part: Vec<FilePart>,
    down_chan: Option<tokio::sync::oneshot::Sender<bool>>,
    /// 文件实际保存路径，包含文件名
    save_path: String,
    /// 任务完成标志(没有发生错误)
    is_done: bool,
    first_err: Option<String>,
}

#[derive(Debug, Clone)]
pub struct FilePart {
    start: i64,
    end: i64,
}

impl FileReceiver {
    fn new() -> Self {
        Self {
            file: Arc::new(TokioMutex::new(HashMap::new())),
            ops: Arc::new(TokioMutex::new(HashMap::new())),
        }
    }

    pub async fn get_file(
        &self,
        head: &crate::route::RouteHead,
    ) -> std::io::Result<tokio::fs::File> {
        let file_id = head.file_id;
        let file_size = head.file_size;
        // debug!("create file: {}", file_path);
        let actual_save_path;
        let already_exist;
        let file_recv_map = &mut self.file.lock().await;
        if let Some(info) = file_recv_map.get(&file_id) {
            actual_save_path = info.save_path.clone();
            already_exist = true;
        } else {
            already_exist = false;
            let file_path =
                std::path::Path::new(&crate::config::GLOBAL_CONFIG.lock().unwrap().save_path)
                    .join(&head.file_name);
            actual_save_path = generate_unique_filepath(file_path)?;
        }
        debug!("create file: {}", actual_save_path);
        let file = tokio::fs::OpenOptions::new()
            .create(true)
            .write(true)
            .open(&actual_save_path)
            .await?;
        if already_exist {
            return Ok(file);
        }

        let (tx, rx) = tokio::sync::oneshot::channel();
        let info = RecvFileInfo {
            exp_size: file_size,
            _file_id: file_id,
            part_lock: TokioMutex::new(()),
            part: Vec::new(),
            down_chan: Some(tx),
            save_path: actual_save_path,
            is_done: false,
            first_err: None,
        };
        file_recv_map.insert(file_id, info);
        // check is this opID exist
        let ops_map = &mut self.ops.lock().await;
        if let None = ops_map.get(&head.op_id) {
            ops_map.insert(
                head.op_id,
                OpInfo {
                    exp_num: head.files_count_in_this_op,
                    succ_num: 0,
                    fail_num: 0,
                },
            );
        }
        crate::RUNTIME.get().unwrap().spawn(recv_monitor(
            self.file.clone(),
            self.ops.clone(),
            file_id,
            head.op_id,
            rx,
        ));
        Ok(file)
    }

    /// 返回值：(是否完成，是否发生错误(不包括自己))
    pub async fn report_file_part(
        &self,
        file_id: u32,
        start: i64,
        end: i64,
        recv_err: Option<String>,
    ) -> (bool, bool) {
        let files_recv = &mut self.file.lock().await;
        let file = match files_recv.get_mut(&file_id) {
            Some(file) => file,
            None => return (false, true),
        };
        let part_lock = file.part_lock.lock().await;
        if file.is_done {
            return (true, false);
        }
        if file.first_err.is_some() {
            return (false, true);
        }
        if let Some(err) = recv_err {
            file.first_err = Some(err);
            file.down_chan.take().unwrap().send(false).ok();
            return (false, false);
        }
        file.part.push(FilePart { start, end });
        let done = self.check(file.part.clone(), file.exp_size).await;
        if done {
            file.is_done = true;
            file.down_chan.take().unwrap().send(true).ok();
        }
        drop(part_lock);
        (done, false)
    }

    pub async fn check(&self, all_part: Vec<FilePart>, exp_size: i64) -> bool {
        let mut part = all_part;
        part.sort_by(|a, b| a.start.cmp(&b.start));
        debug!("file part: {:?}", part);
        if part[0].start != 0 {
            return false;
        }
        let mut cur = 0;
        for i in 0..part.len() {
            cur = std::cmp::max(part[i].end, cur);
            if cur >= exp_size {
                return true;
            }
            if i + 1 >= part.len() {
                return false;
            }
            let next = part[i + 1].start;
            if cur < next {
                return false;
            }
            if cur != next {
                // debug
                error!("file part not continuous:{:?}", part);
            }
        }
        false
    }
}

pub async fn recv_monitor(
    files_recv_info: Arc<TokioMutex<HashMap<u32, RecvFileInfo>>>,
    ops: Arc<TokioMutex<HashMap<u32, OpInfo>>>,
    file_id: u32,
    op_id: u32,
    down_ch: tokio::sync::oneshot::Receiver<bool>,
) {
    use std::time::Duration;
    use tokio::time::sleep;
    let success;
    tokio::select! {
        r = down_ch => {
            if r.is_err() {
               error!("fileID: {} recv report error: {}", file_id, r.err().unwrap());
                success = false;
            } else {
                success = r.unwrap();
            }
        }
        _ = sleep(Duration::from_secs(60*10)) => {
            error!("fileID: {} download timeout!", file_id);
            success = false;
        }
    }
    let ops = &mut ops.lock().await;
    if success {
        ops.get_mut(&op_id).unwrap().succ_num += 1;
    } else {
        ops.get_mut(&op_id).unwrap().fail_num += 1;
    }
    let op_info = ops.get(&op_id).unwrap().clone();
    if op_info.succ_num + op_info.fail_num == op_info.exp_num {
        // 此次操作已经完成
        ops.remove(&op_id);
    }
    // 不管是否下载成功，都要删除，因为下一次传输同一个文件时，fileID是不一样的。
    let file_recv_info = files_recv_info.lock().await.remove(&file_id).unwrap();

    // 仅接收一张图，且格式为png时(only support png)，粘贴到剪切板
    if success
        && op_info.exp_num == 1
        && file_recv_info.exp_size < 1024 * 1024 * 4
        && crate::utils::has_img_ext(&file_recv_info.save_path)
    {
        let image = tokio::fs::read(&file_recv_info.save_path).await;
        if image.is_err() {
            error!(
                "write to clipboard failed:{}",
                image.err().unwrap().to_string()
            );
        } else {
            crate::config::set_clipboard_from_img_bytes(&image.unwrap())
                .await
                .ok();
        }
    }
    // 此次操作已经完成
    if op_info.succ_num + op_info.fail_num == op_info.exp_num {
        let mut msg = format!(
            "{}个文件已保存到 {}",
            op_info.succ_num,
            crate::config::GLOBAL_CONFIG.lock().unwrap().save_path
        );
        if op_info.fail_num > 0 {
            msg = format!("{}\n{}个文件保存失败", msg, op_info.fail_num);
        }
        crate::utils::inform(&msg);
    }
}

/// 产生不冲突的文件路径
fn generate_unique_filepath(path: impl AsRef<std::path::Path>) -> std::io::Result<String> {
    if !path.as_ref().exists() {
        let ret = path
            .as_ref()
            .to_str()
            .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::Other, "path to str error"))?;
        return Ok(ret.to_string());
    }
    let path = path.as_ref();
    let dir = path
        .parent()
        .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::Other, "path parent error"))?;
    let name = path
        .file_name()
        .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::Other, "path file_name error"))?;
    let name: String = name
        .to_str()
        .ok_or_else(|| {
            std::io::Error::new(std::io::ErrorKind::Other, "path file_name to str error")
        })?
        .to_string();
    let file_ext = path
        .extension()
        .unwrap_or(std::ffi::OsStr::new(""))
        .to_str()
        .unwrap_or("")
        .to_string();
    for i in 1..100 {
        let new_name = if !file_ext.is_empty() {
            format!("{}({}).{}", name, i, file_ext)
        } else {
            format!("{}({})", name, i)
        };
        let new_path = dir.join(new_name);
        if !new_path.exists() {
            return Ok(new_path
                .to_str()
                .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::Other, "path to str error"))?
                .to_string());
        }
    }
    Err(std::io::Error::new(
        std::io::ErrorKind::Other,
        "generate unique filepath error, too many files",
    ))
}

lazy_static::lazy_static!(
    pub static ref GLOBAL_FILE_RECEIVER:FileReceiver = FileReceiver::new();
);
