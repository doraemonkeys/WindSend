use crate::RUNTIME;
use std::collections::HashMap;
use std::io::SeekFrom;
use std::sync::Arc;
use std::sync::atomic::Ordering::Relaxed;
use tokio::io::{AsyncReadExt, AsyncSeekExt, Take};
use tokio::sync::Mutex as TokioMutex;
use tracing::{debug, error, warn};

pub struct FilePartReader {
    file_part: Take<tokio::fs::File>,
}

impl FilePartReader {
    /// The file handle cannot be read at the same time anywhere else, or the seek cursor will be wrong.
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

type PullWriteCallback = Box<dyn Fn(&[u8]) + Send>;

pub struct FilePartWriter {
    file_part: tokio::fs::File,
    on_pull_write_ok: Option<PullWriteCallback>,
    pos: usize,
    end: usize,
}

impl FilePartWriter {
    /// The file handle cannot be read at the same time anywhere else, or the seek cursor will be wrong.
    pub async fn new(mut file: tokio::fs::File, start: usize, end: usize) -> std::io::Result<Self> {
        file.seek(SeekFrom::Start(start as u64)).await?;
        Ok(Self {
            file_part: file,
            on_pull_write_ok: None,
            pos: start,
            end,
        })
    }

    pub fn set_on_pull_write_ok<F: 'static + Fn(&[u8]) + Send>(mut self, f: F) -> Self {
        self.on_pull_write_ok = Some(Box::new(f));
        self
    }
}

impl tokio::io::AsyncWrite for FilePartWriter {
    fn poll_write(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        src_buf: &[u8],
    ) -> std::task::Poll<std::io::Result<usize>> {
        let buf_len = src_buf.len();
        let new_src;
        if buf_len + self.pos > self.end {
            warn!(
                "write file error,buf len: {}, pos: {}, end: {}",
                buf_len, self.pos, self.end
            );
            self.pos = self.end;
            new_src = &src_buf[..self.end - self.pos];
        } else {
            new_src = src_buf;
        }
        let poll = std::pin::Pin::new(&mut self.file_part).poll_write(cx, new_src);
        if let std::task::Poll::Ready(Ok(n)) = poll {
            self.pos += n;
            if let Some(f) = &self.on_pull_write_ok {
                f(&new_src[..n]);
            }
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

#[derive(Debug)]
pub struct FileReceiveSessionManager {
    /// key: fileID, value: RecvFileInfo
    ///
    /// fileID is unique for each file transfer session.
    /// All parts of the same file within a single transfer session share the same fileID.
    /// A new fileID is generated for each new transfer session, even if transferring the same file again.
    file_sessions: Arc<TokioMutex<HashMap<u32, Arc<RecvFileInfo>>>>,
    /// key: opID value: OpInfo
    operation_sessions: Arc<TokioMutex<HashMap<u32, OpInfo>>>,
    #[cfg(target_os = "windows")]
    /// Used to synchronize the notification of the progress bar
    notify_lock: Arc<std::sync::Mutex<()>>,
}

/// The progress of the operation is updated in real time.
#[derive(Debug)]
#[allow(dead_code)]
pub struct OpProgress {
    pub success_count: std::sync::atomic::AtomicI32,
    pub failure_count: std::sync::atomic::AtomicI32,
    /// The position of the last progress notification
    pub inform_pos: std::sync::atomic::AtomicU64,
    pub current_pos: std::sync::atomic::AtomicU64,
}

#[derive(Debug, Clone)]
#[allow(dead_code)]
pub struct OpInfo {
    _start_time: std::time::Instant,
    _op_id: u32,
    total_expectation: u64,
    expected_count: i32,
    requested_device_name: Arc<String>,

    progress: Arc<OpProgress>,
}

#[derive(Debug)]
pub struct RecvFileInfo {
    expected_size: i64,
    /// part、is_done、first_err、down_chan
    metadata: TokioMutex<LockedItem>,
}

#[derive(Debug)]
struct LockedItem {
    part: Vec<FilePart>,
    down_chan: Option<tokio::sync::oneshot::Sender<bool>>,
    /// The path where the file is actually saved, including the filename
    save_path: String,
    /// Task completion flag (no error occurred)
    is_done: bool,
    first_err: Option<String>,
}

#[derive(Debug, Clone)]
pub struct FilePart {
    start: i64,
    end: i64,
}

impl FileReceiveSessionManager {
    fn new() -> Self {
        Self {
            file_sessions: Arc::new(TokioMutex::new(HashMap::new())),
            operation_sessions: Arc::new(TokioMutex::new(HashMap::new())),
            #[cfg(target_os = "windows")]
            notify_lock: Arc::new(std::sync::Mutex::new(())),
        }
    }

    pub async fn setup_file_reception(
        self: &Arc<Self>,
        head: &crate::route::protocol::RouteRecvHead,
    ) -> std::io::Result<tokio::fs::File> {
        let file_id = head.file_id;
        let file_size = head.file_size;
        debug!("head.path: {}", head.path);
        let actual_save_path;
        let already_exist;
        let mut file_recv_map = self.file_sessions.lock().await;
        if let Some(info) = file_recv_map.get(&file_id) {
            actual_save_path = info.metadata.lock().await.save_path.clone();
            already_exist = true;
        } else {
            already_exist = false;
            let file_path =
                std::path::Path::new(&crate::config::GLOBAL_CONFIG.read().unwrap().save_path)
                    .join(&head.path);
            actual_save_path = crate::utils::generate_unique_filepath(file_path)?;
        }
        use crate::utils::NormalizePath;
        let actual_save_path = actual_save_path.normalize_path();
        debug!("uploading file: {}", actual_save_path);
        let dir = std::path::Path::new(&actual_save_path)
            .parent()
            .ok_or_else(|| std::io::Error::other("path parent error"))?;
        tokio::fs::create_dir_all(dir).await?;
        let file = tokio::fs::OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(false)
            .open(&actual_save_path)
            .await?;
        if already_exist {
            return Ok(file);
        }

        let mut file = file;
        if head.file_size != 0 {
            // file.set_len(head.file_size as u64).await?;
            use tokio::io::AsyncWriteExt;
            file.seek(SeekFrom::Start((head.file_size - 1) as u64))
                .await?;
            file.write_all(&[0x11]).await?;
        }
        let file = file;

        let (tx, rx) = tokio::sync::oneshot::channel();
        let items = LockedItem {
            part: Vec::new(),
            down_chan: Some(tx),
            save_path: actual_save_path.clone(),
            is_done: false,
            first_err: None,
        };
        let info = RecvFileInfo {
            expected_size: file_size,
            metadata: TokioMutex::new(items),
        };
        file_recv_map.insert(file_id, Arc::new(info));

        // check is this opID exist
        // let ops_map = self.operation_sessions.lock().await;
        // if ops_map.get(&head.op_id).is_none() {
        //     self.create_op_info_inner(head, ops_map);
        // }

        let manager = Arc::clone(self);
        let op_id = head.op_id;
        crate::RUNTIME.spawn(async move {
            manager
                .monitor_single_file_reception(file_id, op_id, actual_save_path, rx)
                .await
        });
        Ok(file)
    }

    pub async fn create_op_info(
        &self,
        head: &crate::route::protocol::RouteRecvHead,
        upload_info: &crate::route::protocol::UploadOperationInfo,
    ) -> Result<(), String> {
        let ops_map = self.operation_sessions.lock().await;
        self.create_op_info_inner(head, upload_info, ops_map)
    }

    fn create_op_info_inner(
        &self,
        head: &crate::route::protocol::RouteRecvHead,
        upload_info: &crate::route::protocol::UploadOperationInfo,
        mut ops_map: tokio::sync::MutexGuard<HashMap<u32, OpInfo>>,
    ) -> Result<(), String> {
        // create new opertion
        let op_info = OpInfo {
            _op_id: head.op_id,
            _start_time: std::time::Instant::now(),
            total_expectation: upload_info.files_size_in_this_op as u64,
            requested_device_name: Arc::new(String::clone(&head.device_name)),
            expected_count: upload_info.files_count_in_this_op,
            progress: Arc::new(OpProgress {
                inform_pos: std::sync::atomic::AtomicU64::new(0),
                current_pos: std::sync::atomic::AtomicU64::new(0),
                success_count: std::sync::atomic::AtomicI32::new(0),
                failure_count: std::sync::atomic::AtomicI32::new(0),
            }),
        };
        #[cfg(not(target_os = "windows"))]
        let old_op = ops_map.insert(head.op_id, op_info);
        #[cfg(target_os = "windows")]
        let old_op = ops_map.insert(head.op_id, OpInfo::clone(&op_info));
        if let Some(old_op) = old_op {
            error!(
                "opID: {} already exist, old op info: {:?}",
                head.op_id, old_op
            );
            ops_map.remove(&head.op_id);
            return Err(format!("opID: {} already exist", head.op_id));
        }

        #[cfg(target_os = "windows")]
        {
            if upload_info.files_count_in_this_op == 0 {
                return Ok(());
            }
            let save_path = crate::config::GLOBAL_CONFIG
                .read()
                .unwrap()
                .save_path
                .clone();
            let progress_tag = format!("{}", head.op_id);
            let title = format!(
                "Total: {}",
                crate::utils::bytes_to_human_readable(upload_info.files_size_in_this_op)
            );
            crate::utils::inform_with_progress(
                Some(&save_path),
                win_toast_notify::Progress {
                    tag: progress_tag.clone(),
                    title,
                    status: "Receiving".to_string(),
                    value: 0f32,
                    value_string: format!("{}/{} 0%", 0, op_info.expected_count),
                },
            );
            let notify_lock = Arc::clone(&self.notify_lock);
            RUNTIME.spawn(async move {
                let mut interval = tokio::time::interval(tokio::time::Duration::from_millis(500));
                let total = op_info.total_expectation;
                let mut useless_times = 0;
                const MAX_USELESS_TIMES: u32 = 150;
                loop {
                    interval.tick().await;
                    let current = op_info.progress.current_pos.load(Relaxed);
                    let inform_pos = op_info.progress.inform_pos.load(Relaxed);
                    let success_count = op_info.progress.success_count.load(Relaxed);
                    let failure_count = op_info.progress.failure_count.load(Relaxed);
                    if current == total {
                        break;
                    }
                    if success_count + failure_count == op_info.expected_count {
                        break;
                    }
                    if useless_times > MAX_USELESS_TIMES {
                        error!("progress loop: useless times exceed limit");
                        break;
                    }
                    if inform_pos == current {
                        useless_times += 1;
                        continue;
                    }
                    let percent = current as f32 / total as f32;
                    if current > total {
                        error!(
                            "current > total: {},total: {},current: {}",
                            current, total, current
                        );
                    }

                    let value_string = format!(
                        "{}/{} {:.2}%",
                        success_count,
                        op_info.expected_count,
                        percent * 100.0
                    );
                    {
                        let _guard = notify_lock.lock().unwrap();
                        if let Err(e) = win_toast_notify::WinToastNotify::progress_update(
                            None,
                            &progress_tag,
                            percent,
                            &value_string,
                        ) {
                            error!("progress update error: {}", e);
                        }
                    }
                    op_info.progress.inform_pos.store(current, Relaxed);
                }
            });
        }
        Ok(())
    }

    pub async fn get_op_progress_handle(&self, op_id: u32) -> Option<Arc<OpProgress>> {
        let ops = self.operation_sessions.lock().await;
        ops.get(&op_id).map(|op| Arc::clone(&op.progress))
    }

    /// return value: (is_done, is_error_occurred(not include self))
    pub async fn report_file_part_completion(
        &self,
        file_id: u32,
        start: i64,
        end: i64,
        recv_err: Option<String>,
    ) -> (bool, bool) {
        let recv_file;
        {
            let files_recv = self.file_sessions.lock().await;
            recv_file = match files_recv.get(&file_id) {
                Some(file) => file.clone(),
                None => return (false, true),
            };
        }
        let mut recv_items = recv_file.metadata.lock().await;
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
        let done = self
            .verify_file_completeness(&mut recv_items.part, recv_file.expected_size)
            .await;
        if done {
            recv_items.is_done = true;
            recv_items.down_chan.take().unwrap().send(true).ok();
        }
        (done, false)
    }

    pub async fn verify_file_completeness(
        &self,
        all_part: &mut Vec<FilePart>,
        exp_size: i64,
    ) -> bool {
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
    pub async fn monitor_single_file_reception(
        // files_recv_info: Arc<TokioMutex<HashMap<u32, Arc<RecvFileInfo>>>>,
        // ops: Arc<TokioMutex<HashMap<u32, OpInfo>>>,
        &self,
        file_id: u32,
        op_id: u32,
        file_path: String,
        down_ch: tokio::sync::oneshot::Receiver<bool>,
    ) {
        use std::time::Duration;
        use tokio::time::sleep;
        let success;
        let mut is_timeout = false;

        tokio::select! {
            r = down_ch => {
                if let Err(e) = r {
                    error!("fileID: {} recv report error: {}", file_id, e);
                    success = false;
                } else {
                    success = r.unwrap();
                }
            }
            r = async {
                    let mut temp_file_size = 0;
                    loop {
                        sleep(Duration::from_secs(60*10)).await;
                        let file_size = tokio::fs::metadata(&file_path)
                            .await.map(|m| m.len());
                        if let Err(e) = file_size {
                            is_timeout = true;
                            // maybe file deleted by user
                            warn!("cannot get {} metadata: {}", file_path, e);
                            return false;
                        }
                        let file_size = file_size.unwrap();
                        if file_size == temp_file_size {
                            error!("fileID: {} download timeout!", file_id);
                            is_timeout = true;
                            return false;
                        }
                        temp_file_size = file_size;
                    }
            } => {
                success = r;
            }
        }

        let op_info = self
            .operation_sessions
            .lock()
            .await
            .get(&op_id)
            .unwrap()
            .clone();

        if success {
            op_info.progress.success_count.fetch_add(1, Relaxed);
        } else {
            op_info.progress.failure_count.fetch_add(1, Relaxed);
        }

        // It should be deleted regardless of whether the download was successful or not,
        // because the fileID will not be the same next time the same file is transferred.
        let file_recv_info = self.file_sessions.lock().await.remove(&file_id).unwrap();

        // Paste it to the clipboard if only receive one image
        let save_path = &file_recv_info.metadata.lock().await.save_path;
        if success
            && op_info.expected_count == 1
            && file_recv_info.expected_size < 1024 * 1024 * 4
            && crate::utils::has_img_ext(save_path)
        {
            let image = tokio::fs::read(save_path).await;
            if let Err(e) = image {
                error!("write to clipboard failed:{}", e);
            } else {
                RUNTIME.spawn(async move {
                    let _ = crate::config::CLIPBOARD.write_image_from_bytes(&image.unwrap());
                });
            }
        }

        let success_count = op_info.progress.success_count.load(Relaxed);
        let failure_count = op_info.progress.failure_count.load(Relaxed);
        if success_count + failure_count == op_info.expected_count {
            // This operation has been completed
            self.operation_sessions.lock().await.remove(&op_id);
        }
        // tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
        if !is_timeout && success_count + failure_count == op_info.expected_count {
            #[cfg(not(target_os = "windows"))]
            {
                use crate::language::LanguageKey;
                let save_path = &crate::config::GLOBAL_CONFIG.read().unwrap().save_path;
                let mut msg = format!(
                    "{} {} {}",
                    success_count,
                    LanguageKey::NFilesSavedTo.translate(),
                    save_path
                );
                if failure_count > 0 {
                    msg = format!("{}\n{} files failed to save", msg, failure_count);
                }
                crate::utils::inform(&msg, &op_info.requested_device_name, Some(save_path));
            }
            #[cfg(target_os = "windows")]
            {
                let progress_tag = format!("{}", op_id);
                let value_string = format!("{}/{} files", success_count, op_info.expected_count);
                let _guard = self.notify_lock.lock().unwrap();
                let _ = win_toast_notify::WinToastNotify::progress_complete(
                    None,
                    &progress_tag,
                    &format!("Completed, costing: {:?}", op_info._start_time.elapsed()),
                    &value_string,
                );
            }
        }
    }
}

lazy_static::lazy_static!(
    pub static ref GLOBAL_RECEIVER_SESSION_MANAGER:Arc<FileReceiveSessionManager> = Arc::new(FileReceiveSessionManager::new());
);
