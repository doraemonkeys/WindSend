package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"

	"github.com/doraemonkeys/WindSend/language"
	"github.com/sirupsen/logrus"
)

type FileReceiver struct {
	// key: fileID value: RecvFileInfo
	//
	// fileID在每次传输一个文件时都是随机的，
	// 即使再次传输同一个文件，也会重新生成一个fileID
	file map[uint32]*recvfileInfo
	OPs  map[uint32]*OpInfo
	// 用于保证file和Ops的并发安全
	lock *sync.Mutex
}

type OpInfo struct {
	op      uint32
	reqHead headInfo
	expNum  int
	succNum int
	failNum int
}

type recvfileInfo struct {
	file     *os.File
	filePath string
	partLock *sync.Mutex
	part     []FilePart
	expSize  int64
	downChan chan bool
	// 任务完成标志
	isDone   bool
	firstErr error
}

type FilePart struct {
	start int64
	end   int64
}

func (f *FileReceiver) GetFile(head headInfo) (*os.File, error) {
	var (
		fileID   uint32 = head.FileID
		fileSize int64  = head.FileSize
		filePath string = filepath.Join(GloballCnf.SavePath, head.Path)
	)

	filePath = filepath.Clean(filePath)
	f.lock.Lock()
	defer f.lock.Unlock()
	if file, ok := f.file[fileID]; ok {
		return file.file, nil
	}
	filePath = generateUniqueFilepath(filePath)
	err := os.MkdirAll(filepath.Dir(filePath), 0666)
	if err != nil {
		return nil, err
	}
	file, err := os.OpenFile(filePath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0666)
	if err != nil {
		return nil, err
	}
	var Info = &recvfileInfo{file: file, filePath: filePath, expSize: fileSize}
	Info.partLock = new(sync.Mutex)
	Info.downChan = make(chan bool, 1)
	f.file[fileID] = Info

	// check is this opID exist
	if _, ok := f.OPs[head.OpID]; !ok {
		f.OPs[head.OpID] = &OpInfo{
			op:      head.OpID,
			reqHead: head,
			expNum:  head.FilesCountInThisOp,
		}
	}

	go f.recvMonitor(fileID, head.OpID, Info.downChan)
	return file, nil
}

func (f *FileReceiver) recvMonitor(fileID uint32, opID uint32, downCh chan bool) {
	var success bool = false
	var isTimeout bool = false
	select {
	case success = <-downCh:
	case <-time.After(time.Minute * 60):
		isTimeout = true
		success = false
		logrus.Error("fileID:", fileID, "download timeout!")
	}

	f.lock.Lock()
	if success {
		f.OPs[opID].succNum++
	} else {
		f.OPs[opID].failNum++
	}
	fileInfo := f.file[fileID]
	OpInfo := f.OPs[opID]
	fileInfo.file.Close()
	fileInfo.file = nil // 防止再次使用
	// 不管是否下载成功，都要删除，因为下一次传输同一个文件时，fileID是不一样的。
	delete(f.file, fileID)
	// 此次操作已经完成
	if OpInfo.succNum+OpInfo.failNum == OpInfo.expNum {
		delete(f.OPs, opID)
	}
	f.lock.Unlock()

	// 仅接收一张图，粘贴到剪切板
	if success && OpInfo.expNum == 1 &&
		fileInfo.expSize < 1024*1024*4 &&
		HasImageExt(fileInfo.filePath) {
		go func() {
			now := time.Now()
			err := SetImageToClipboard(fileInfo.filePath)
			if err != nil {
				logrus.Warningln("SetImageToClipboard error:", err)
			}
			logrus.Debugln("SetImageToClipboard cost:", time.Since(now))
		}()
	}
	// 此次操作已经完成
	if !isTimeout && OpInfo.succNum+OpInfo.failNum == OpInfo.expNum {
		msg := fmt.Sprintf("%d %s %s", OpInfo.succNum, language.Translate(language.NFilesSavedTo), GloballCnf.SavePath)
		if OpInfo.failNum > 0 {
			msg += fmt.Sprintf("\n%d files failed to save", OpInfo.failNum)
		}
		Inform(msg, OpInfo.reqHead.DeviceName)
	}
}

// previousErr是不同连接接收同一个文件时，第一个连接发生的错误(不包括自己)，如果没有错误，则为nil
func (f *FileReceiver) ReportFilePart(fileID uint32, start, end int64, recvErr error) (done bool, errOccurred bool) {
	var file *recvfileInfo
	var ok bool

	f.lock.Lock()
	file, ok = f.file[fileID]
	f.lock.Unlock()
	// 可能已经发生错误，fileID已经被删除了
	if !ok {
		return false, true
	}

	file.partLock.Lock()
	defer file.partLock.Unlock()
	if file.isDone {
		return true, false
	}
	if file.firstErr != nil {
		return false, true
	}
	if recvErr != nil {
		file.firstErr = recvErr
		file.downChan <- false
		return false, false
	}
	file.part = append(file.part, FilePart{start: start, end: end})
	done = f.check(fileID, file)
	if done {
		file.isDone = true
		file.downChan <- true
	}
	return done, false
}

// 检查是否完成
func (f *FileReceiver) check(fileID uint32, file *recvfileInfo) bool {
	sort.Slice(file.part, func(i, j int) bool {
		return file.part[i].start < file.part[j].start
	})
	if file.part[0].start != 0 {
		return false
	}
	var cur int64 = 0
	for i := 0; i < len(file.part); i++ {
		cur = max(file.part[i].end, cur)
		if cur >= file.expSize {
			return true
		}
		if i+1 >= len(file.part) {
			return false
		}
		var next = file.part[i+1].start
		if cur < next {
			return false
		}
		if cur != next {
			// debug
			logrus.Errorf("file part not continuous:%v", file.part)
		}
	}
	return false
}

func NewFileReceiver() *FileReceiver {
	var r = &FileReceiver{
		lock: new(sync.Mutex),
	}
	r.file = make(map[uint32]*recvfileInfo)
	r.OPs = make(map[uint32]*OpInfo)
	return r
}

var GlobalFileReceiver = NewFileReceiver()

func pasteFileHandler(conn net.Conn, head headInfo) (noSocketErr bool) {
	if head.UploadType == pathInfoTypeDir {
		return createDirOnlyHandler(conn, head)
	}
	// head.End == 0 && head.Start == 0 表示文件为空
	if head.End <= head.Start && !(head.End == 0 && head.Start == 0) {
		errMsg := fmt.Sprintf("invalid file part, start:%d, end:%d", head.Start, head.End)
		logrus.Error(errMsg)
		return respCommonError(conn, errMsg)
	}
	dataLen := head.End - head.Start
	if head.DataLen != dataLen {
		errMsg := fmt.Sprintf("invalid file part, dataLen:%d, start:%d, end:%d", head.DataLen, head.Start, head.End)
		logrus.Error(errMsg)
		return respCommonError(conn, errMsg)
	}
	if head.FilesCountInThisOp == 0 {
		errMsg := fmt.Sprintf("invalid file part, FilesCountInThisOp:%d", head.FilesCountInThisOp)
		logrus.Error(errMsg)
		return respCommonError(conn, errMsg)
	}

	var bufSize = max(int(dataLen/8), 4096) // 8 is a magic number
	// fmt.Println("bufSize:", bufSize)
	reader := bufio.NewReaderSize(conn, bufSize)
	file, err := GlobalFileReceiver.GetFile(head)
	if err != nil {
		logrus.Error("create file error:", err)
		return respCommonError(conn, err.Error())
	}
	fileWriter := NewFileWriter(file, int(head.Start), int(head.End))
	// fileBufWriter := bufio.NewWriterSize(fileWriter, bufSize)
	// n, err := io.CopyN(fileWriter, reader, dataLen)
	n, err := io.CopyN(fileWriter, reader, dataLen)
	// n, err := reader.WriteTo(fileWriter)
	if err != nil && err != io.EOF {
		logrus.Error("write file error:", err)
		GlobalFileReceiver.ReportFilePart(head.FileID, head.Start, head.End, err)
		return respCommonError(conn, err.Error())
	}
	if n < dataLen {
		logrus.Errorln("write file error, n:", n, " dataLen:", dataLen)
		GlobalFileReceiver.ReportFilePart(head.FileID, head.Start, head.End, errors.New(ErrorIncompleteData))
		return respCommonError(conn, ErrorIncompleteData)
	}
	if n > dataLen {
		// should not happen
		logrus.Warnln("write file error, n:", n, "dataLen:", dataLen)
	}
	// part written successfully
	noSocketErr = true
	err = sendMsg(conn, fmt.Sprintf("file part written successfully, fileID:%d, start:%d, end:%d", head.FileID, head.Start, head.End))
	if err != nil {
		noSocketErr = false
	}
	logrus.Debugln("write file part success, fileID:", head.FileID, " start:", head.Start, " end:", head.End)
	done, errOccurred := GlobalFileReceiver.ReportFilePart(head.FileID, head.Start, head.End, nil)
	if errOccurred {
		return true
	}
	if done {
		logrus.Infoln("save file success:", head.Path)
	}
	return noSocketErr
}

func createDirOnlyHandler(conn net.Conn, head headInfo) (noSocketErr bool) {
	var buf = make([]byte, head.DataLen)
	_, err := io.ReadFull(conn, buf)
	if err != nil {
		logrus.Error("read dir data error:", err)
		return respCommonError(conn, err.Error())
	}
	var dirs []string
	err = json.Unmarshal(buf, &dirs)
	if err != nil {
		logrus.Error("unmarshal dir data error:", err)
		return respCommonError(conn, err.Error())
	}
	for i := 0; i < len(dirs); i++ {
		err := os.MkdirAll(filepath.Join(GloballCnf.SavePath, dirs[i]), 0666)
		if err != nil {
			logrus.Error("create dir error:", err)
			return respCommonError(conn, err.Error())
		}
	}
	err = sendMsg(conn, "create dirs success")
	if err != nil {
		logrus.Error("createDirOnlyHandler sendMsg error:", err)
		return false
	}
	if len(dirs) > 0 && head.FilesCountInThisOp == 0 {
		Inform(language.Translate(language.DirCreated), head.DeviceName)
	}
	return true
}

type FileWriter struct {
	pos  int
	end  int
	file *os.File
}

func NewFileWriter(file *os.File, pos int, end int) *FileWriter {
	return &FileWriter{
		pos:  pos,
		end:  end,
		file: file,
	}
}

func (fw *FileWriter) Write(p []byte) (n int, err error) {
	if len(p)+fw.pos > fw.end {
		logrus.Warnln("write file error, len(p):", len(p), " pos:", fw.pos, " end:", fw.end)
		p = p[:fw.end-fw.pos]
	}
	n, err = fw.file.WriteAt(p, int64(fw.pos))
	fw.pos += n
	if fw.pos >= fw.end && err == nil {
		err = io.EOF
	}
	return
}
