// socket_stick/server/main.go
package main

import (
	"crypto/tls"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"
)

type FileReceiver struct {
	fileLock *sync.Mutex
	file     map[uint32]*filePartInfo
}

type filePartInfo struct {
	file     *os.File
	fileID   uint32
	partLock *sync.Mutex
	part     []FilePart
	expSize  int64
	downChan chan struct{}
}

func (f *FileReceiver) GetFile(fileID uint32, fileSize int64, filePath string) (*os.File, error) {
	filePath = filepath.Clean(filePath)
	f.fileLock.Lock()
	defer f.fileLock.Unlock()
	if file, ok := f.file[fileID]; ok {
		return file.file, nil
	}
	filePath = generateUniqueFilepath(filePath)
	file, err := os.OpenFile(filePath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0666)
	if err != nil {
		return nil, err
	}
	var Info = &filePartInfo{file: file, fileID: fileID, expSize: fileSize}
	Info.partLock = new(sync.Mutex)
	Info.downChan = make(chan struct{}, 1)
	f.file[fileID] = Info
	go f.recvMonitor(fileID, Info.downChan)
	return file, nil
}

func (f *FileReceiver) recvMonitor(fileID uint32, downCh chan struct{}) {
	select {
	case <-downCh:
		fmt.Println("fileID:", fileID, "download complete!")
		return
	case <-time.After(time.Minute * 5):
		f.fileLock.Lock()
		delete(f.file, fileID)
		f.fileLock.Unlock()
		fmt.Println("fileID:", fileID, "download timeout!")
		return
	}
}

func (f *FileReceiver) SetFilePart(fileID uint32, start, end int64) {
	f.fileLock.Lock()
	defer f.fileLock.Unlock()
	if file, ok := f.file[fileID]; ok {
		file.partLock.Lock()
		defer file.partLock.Unlock()
		file.part = append(file.part, FilePart{start: start, end: end})
		f.checkAndSave(fileID, file)
	}
}

func (f *FileReceiver) checkAndSave(fileID uint32, file *filePartInfo) {
	sort.Slice(file.part, func(i, j int) bool {
		return file.part[i].start < file.part[j].start
	})
	fmt.Println("file.part:", file.part)
	if file.part[0].start != 0 {
		return
	}
	var cur int64 = 0
	for i := 0; i < len(file.part); i++ {
		cur = max(file.part[i].end, cur)
		fmt.Println("part:", i, "cur:", cur)
		if cur >= file.expSize {
			fmt.Println("file part complete!")
			file.file.Close()
			delete(f.file, fileID)
			file.downChan <- struct{}{}
			return
		}
		if i+1 >= len(file.part) {
			fmt.Println(1)
			return
		}
		var next = file.part[i+1].start
		if cur < next {
			fmt.Println(2)
			return
		}
		if cur != next {
			// debug用，后面可以删除
			fmt.Println("file part not continuous")
			return
		}
	}
}

type Ordered interface {
	~int8 | ~int16 | ~int32 | ~int64 | ~uint8 | ~uint16 |
		~uint32 | ~uint64 | ~int
}

func max[T Ordered](a, b T) T {
	if a > b {
		return a
	}
	return b
}

func NewFileReceiver() *FileReceiver {
	var r = &FileReceiver{
		fileLock: new(sync.Mutex),
	}
	r.file = make(map[uint32]*filePartInfo)
	return r
}

// 产生不冲突的文件名
func generateUniqueFilepath(filePath string) string {
	if _, err := os.Stat(filePath); err != nil {
		return filePath
	}
	name := filepath.Base(filePath)
	fileExt := filepath.Ext(name)
	name = name[:len(name)-len(fileExt)]
	for i := 1; ; i++ {
		if fileExt != "" {
			filePath = filepath.Join(dir, fmt.Sprintf("%s(%d).%s", name, i, fileExt))
		} else {
			filePath = filepath.Join(dir, fmt.Sprintf("%s(%d)", name, i))
		}
		if _, err := os.Stat(filePath); err != nil {
			return filePath
		}
	}
}

type FilePart struct {
	start int64
	end   int64
}

const dir = "./"

var fileReceiver = NewFileReceiver()

func main() {

	// listen, err := net.Listen("tcp", ":6779")
	// if err != nil {
	// 	fmt.Println("listen failed, err:", err)
	// 	return
	// }
	// defer listen.Close()
	cert, err := tls.LoadX509KeyPair("./tls/cert.pem", "./tls/key.pem")
	if err != nil {
		panic(err)
	}
	config := &tls.Config{
		Certificates: []tls.Certificate{cert},
		// 是否跳过证书验证
		InsecureSkipVerify: true,
		MaxVersion:         tls.VersionTLS12,
	}
	listen, err := tls.Listen("tcp", ":6779", config)
	if err != nil {
		fmt.Println("listen failed, err:", err)
		return
	}
	defer listen.Close()
	for {
		conn, err := listen.Accept()
		if err != nil {
			fmt.Println("accept failed, err:", err)
			continue
		}
		go process(conn)
	}
}

// 换 int64

// acton 1 byte 1:send 2:get
// tokenLen 4 byte
// token n byte
// fileID 4 byte
// fileSize 4 byte
// nameLen 4 byte
// name n byte
// range-start 4 byte
// range-end 4 byte
// data n byte

// -------+--------+---------+--------+---------+
// 4 byte | n byte |  4 byte | 4 byte | n byte  |
// -------+--------+---------+--------+---------+
//  nLen  |  name  |  start  |  end   |  data   |

// --------+--------+---------+--------+---------+---------+---------+
//  4 byte | 4 byte |  4 byte | n byte |  4 byte |  4 byte |  n byte |
// --------+--------+---------+--------+---------+---------+---------+
//  fileID | fSize  |  nLen   |  name  |  start  |   end   |  data   |

// acton 1 byte 1:send 2:get
// tokenLen 4 byte
// token n byte
// pathLen 4 byte
// path n byte
// range-start 4 byte
// range-end 4 byte
// data n byte

type UploadHeadInfo struct {
	Action   string `json:"action"`
	TimeIp   string `json:"timeIp"`
	FileID   uint32 `json:"fileID"`
	FileSize int64  `json:"fileSize"`
	Path     string `json:"path"`
	Name     string `json:"name"`
	Start    int64  `json:"start"`
	End      int64  `json:"end"`
}

type DownloadHeadInfo struct {
	Action string `json:"action"`
	TimeIp string `json:"timeIp"`
	Path   string `json:"path"`
	Start  int64  `json:"start"`
	End    int64  `json:"end"`
}

func process(conn net.Conn) {
	defer conn.Close()

	const headBufSize = 1024
	var headBuf [headBufSize]byte

	// 读取json长度
	var headLen int32
	if _, err := io.ReadFull(conn, headBuf[:4]); err != nil {
		fmt.Println("read head len failed, err:", err)
		return
	}
	headLen = int32(binary.LittleEndian.Uint32(headBuf[:4]))
	fmt.Println("headLen:", headLen)
	// 读取json
	if _, err := io.ReadFull(conn, headBuf[:headLen]); err != nil {
		fmt.Println("read head failed, err:", err)
		return
	}
	var head DownloadHeadInfo
	if err := json.Unmarshal(headBuf[:headLen], &head); err != nil {
		fmt.Println("json unmarshal failed, err:", err)
		return
	}
	fmt.Printf("head:%+v\n", head)

	file, err := os.Open(head.Path)
	if err != nil {
		fmt.Println("open file failed, err:", err)
		return
	}
	defer file.Close()

	expectedSize := head.End - head.Start
	const maxBufSize = 1024 * 1024 * 50 // 后续改30
	var bufSize = min(expectedSize, maxBufSize)
	fmt.Println("bufSize:", bufSize/1024/1024, "MB")
	var filereader = NewFilePartReader(file, int(head.Start), int(head.End))
	var buf = make([]byte, bufSize)
	var written int
	for {
		n, err := filereader.Read(buf)
		if err != nil {
			if err == io.EOF {
				_, err := conn.Write(buf[:n])
				if err != nil {
					fmt.Println("write failed, err:", err)
					return
				}
				written += n
				if written > int(expectedSize) {
					fmt.Println("write size not match, expected:", expectedSize, "actual:", written)
					return
				}
				fmt.Println("write size:", n)
				fmt.Println("read file finished")
				break
			}
			fmt.Println("read file failed, err:", err)
			return
		}
		fmt.Println("read size:", n)
		written += n
		_, err = conn.Write(buf[:n])
		if err != nil {
			fmt.Println("write failed, err:", err)
			return
		}
		fmt.Println("write size:", n)
		if written > int(expectedSize) {
			fmt.Println("write size not match, expected:", expectedSize, "actual:", written)
			return
		}
		if written == int(expectedSize) {
			fmt.Println("read file finished")
			break
		}
	}

	// var reader = bufio.NewReaderSize(filereader, int(bufSize))
	// n, err := reader.WriteTo(conn)
	// if err != nil {
	// 	fmt.Println("write failed, err:", err)
	// 	return
	// }
	// fmt.Println("write size:", n)
	// if n != expectedSize {
	// 	fmt.Println("write size not match, expected:", expectedSize, "actual:", n)
	// }
}

func min[T Ordered](a, b T) T {
	if a < b {
		return a
	}
	return b
}

type FileWriter struct {
	pos  int
	file *os.File
}

func NewFileWriter(file *os.File, pos int) *FileWriter {
	return &FileWriter{
		pos:  pos,
		file: file,
	}
}

func (fw *FileWriter) Write(p []byte) (n int, err error) {
	n, err = fw.file.WriteAt(p, int64(fw.pos))
	fw.pos += n
	return
}

type FilePartReader struct {
	file    *os.File
	start   int
	end     int
	written int
}

// [start, end)
func NewFilePartReader(file *os.File, start, end int) *FilePartReader {
	return &FilePartReader{
		file:  file,
		start: start,
		end:   end,
	}
}
func (fr *FilePartReader) Read(p []byte) (n int, err error) {
	if fr.written >= fr.end-fr.start {
		return 0, io.EOF
	}
	n, err = fr.file.ReadAt(p, int64(fr.start+fr.written))
	if fr.written+n > fr.end-fr.start {
		n = fr.end - fr.start - fr.written
		fr.written = fr.end - fr.start
	} else {
		fr.written += n
	}
	return
}
