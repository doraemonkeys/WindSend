use crate::language::{LanguageKey, LANGUAGE_MANAGER};
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
    /// key: fileID value: RecvFileInfo
    ///
    /// fileID在每次传输一个文件时都是随机的，
    /// 即使再次传输同一个文件，也会重新生成一个fileID
    file: Arc<TokioMutex<HashMap<u32, Arc<RecvFileInfo>>>>,
    /// key: opID value: OpInfo
    ops: Arc<TokioMutex<HashMap<u32, OpInfo>>>,
}

#[derive(Debug, Clone)]
pub struct OpInfo {
    req_device_name: String,
    exp_num: i32,
    succ_num: i32,
    fail_num: i32,
}

#[derive(Debug)]
pub struct RecvFileInfo {
    exp_size: i64,
    /// part、is_done、first_err、down_chan
    items: TokioMutex<LockedItem>,
}

#[derive(Debug)]
struct LockedItem {
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
        head: &crate::route::RouteRecvHead,
    ) -> std::io::Result<tokio::fs::File> {
        let file_id = head.file_id;
        let file_size = head.file_size;
        // debug!("create file: {}", file_path);
        let actual_save_path;
        let already_exist;
        let mut file_recv_map = self.file.lock().await;
        if let Some(info) = file_recv_map.get(&file_id) {
            actual_save_path = info.items.lock().await.save_path.clone();
            already_exist = true;
        } else {
            already_exist = false;
            let file_path =
                std::path::Path::new(&crate::config::GLOBAL_CONFIG.lock().unwrap().save_path)
                    .join(&head.path);
            actual_save_path = generate_unique_filepath(file_path)?;
        }
        debug!("uploading file: {}", actual_save_path);
        let dir = std::path::Path::new(&actual_save_path)
            .parent()
            .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::Other, "path parent error"))?;
        tokio::fs::create_dir_all(dir).await?;
        let file = tokio::fs::OpenOptions::new()
            .create(true)
            .write(true)
            .open(&actual_save_path)
            .await?;
        if already_exist {
            return Ok(file);
        }

        let (tx, rx) = tokio::sync::oneshot::channel();
        let items = LockedItem {
            part: Vec::new(),
            down_chan: Some(tx),
            save_path: actual_save_path,
            is_done: false,
            first_err: None,
        };
        let info = RecvFileInfo {
            exp_size: file_size,
            items: TokioMutex::new(items),
        };
        file_recv_map.insert(file_id, Arc::new(info));
        // check is this opID exist
        let mut ops_map = self.ops.lock().await;
        if let None = ops_map.get(&head.op_id) {
            ops_map.insert(
                head.op_id,
                OpInfo {
                    req_device_name: head.device_name.clone(),
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
        let recv_file;
        {
            let files_recv = self.file.lock().await;
            recv_file = match files_recv.get(&file_id) {
                Some(file) => file.clone(),
                None => return (false, true),
            };
        }
        let mut recv_items = recv_file.items.lock().await;
        if recv_items.is_done {
            return (true, false);
        }
        if recv_items.first_err.is_some() {
            return (false, true);
        }
        if let Some(err) = recv_err {
            recv_items.first_err = Some(err);
            recv_items.down_chan.take().unwrap().send(false).ok();
            return (false, false);
        }
        recv_items.part.push(FilePart { start, end });
        let done = self.check(&mut recv_items.part, recv_file.exp_size).await;
        if done {
            recv_items.is_done = true;
            recv_items.down_chan.take().unwrap().send(true).ok();
        }
        (done, false)
    }

    pub async fn check(&self, all_part: &mut Vec<FilePart>, exp_size: i64) -> bool {
        let part = all_part;
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
    files_recv_info: Arc<TokioMutex<HashMap<u32, Arc<RecvFileInfo>>>>,
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
            if let Err(e) = r {
                error!("fileID: {} recv report error: {}", file_id, e);
                success = false;
            } else {
                success = r.unwrap();
            }
        }
        //TODO: remove this timeout
        _ = sleep(Duration::from_secs(60*60)) => {
            error!("fileID: {} download timeout!", file_id);
            success = false;
        }
    }
    let mut ops = ops.lock().await;
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

    // 仅接收一张图，粘贴到剪切板
    let save_path = &file_recv_info.items.lock().await.save_path;
    if success
        && op_info.exp_num == 1
        && file_recv_info.exp_size < 1024 * 1024 * 4
        && crate::utils::has_img_ext(save_path)
    {
        let image = tokio::fs::read(save_path).await;
        if let Err(e) = image {
            error!("write to clipboard failed:{}", e);
        } else {
            let _ = crate::config::set_clipboard_from_img_bytes(&image.unwrap()).await;
        }
    }

    let files_saved_to = LANGUAGE_MANAGER
        .read()
        .unwrap()
        .translate(LanguageKey::NFilesSavedTo);
    // 此次操作已经完成
    if op_info.succ_num + op_info.fail_num == op_info.exp_num {
        let mut msg = format!(
            "{} {} {}",
            op_info.succ_num,
            files_saved_to,
            crate::config::GLOBAL_CONFIG.lock().unwrap().save_path
        );
        if op_info.fail_num > 0 {
            msg = format!("{}\n{} files failed to save", msg, op_info.fail_num);
        }
        crate::utils::inform(&msg, &op_info.req_device_name);
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
    let name: String = name.to_string_lossy().to_string();
    let file_ext = path
        .extension()
        .unwrap_or(std::ffi::OsStr::new(""))
        .to_str()
        .unwrap_or("")
        .to_string();
    for i in 1..100 {
        let new_name = if !file_ext.is_empty() {
            let name = name.trim_end_matches(&format!(".{}", file_ext));
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
