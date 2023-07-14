package main

import (
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"strings"
	"time"

	"github.com/sirupsen/logrus"
	"golang.design/x/clipboard"
)

const TimeFormat = "2006-01-02 15:04:05"
const MaxTimeDiff float64 = 10

const (
	// 服务器内部错误
	ErrorInternal = "internal error"
	// 无效的验证数据
	ErrorInvalidAuthData = "invalid auth data"
	// 过期的验证数据
	ErrorExpiredAuthData = "expired auth data"
	// 剪切板数据为空
	ErrorClipboardDataEmpty = "你还没有复制任何内容"
	// 剪切板数据过大
	ErrorClipboardDataTooLarge = "clipboard data too large"
	// 损坏的数据
	ErrorInvalidData = "invalid data"
	// 不完整的数据
	ErrorIncompleteData = "incomplete data"
)

const (
	pasteTextAction = "pasteText"
	pasteFileAction = "pasteFile"
	copyAction      = "copy"
	pingAction      = "ping"
	downloadAction  = "download"
	webIp           = "web"
)

type headInfo struct {
	Action   string `json:"action"`
	TimeIp   string `json:"timeIp"`
	FileID   uint32 `json:"fileID"`
	FileSize int64  `json:"fileSize"`
	Path     string `json:"path"`
	Name     string `json:"name"`
	Start    int64  `json:"start"`
	End      int64  `json:"end"`
	DataLen  int64  `json:"dataLen"`
	// 操作ID
	OpID uint32 `json:"opID"`
	// 此次操作想要上传的文件数量
	FilesCountInThisOp int `json:"filesCountInThisOp"`
	// Msg      string `json:"msg"`
}

type RespHead struct {
	Code int `json:"code"`
	// TimeIp string   `json:"timeIp"`
	Msg string `json:"msg"`
	// 客户端copy时返回的数据类型(text, image, file)
	DataType string `json:"dataType"`
	// 如果body有数据，返回数据的长度
	DataLen int64      `json:"dataLen"`
	Paths   []pathInfo `json:"paths"`
}

type pathInfo struct {
	Path string `json:"path"`
	Size int64  `json:"size"`
}

const (
	DataTypeText      = "text"
	DataTypeClipImage = "clip-image"
	DataTypeFilePaths = "files"
	DataTypeBinary    = "binary"
)

var panicWriter = NewLazyFileWriter("panic.log")

func mainProcess(conn net.Conn) {
	defer func() {
		if err := recover(); err != nil {
			logrus.Error("panic:", err)
			panicWriter.Write([]byte(fmt.Sprintf("%v\n", err)))
		}
	}()

	defer conn.Close()

	head, ok := commonAuth(conn)
	if !ok {
		return
	}
	logrus.Debugf("head: %+v", head)

	switch head.Action {
	case pingAction:
		pingHandler(conn, head)
		return
	case pasteTextAction:
		pasteTextHandler(conn, head)
		return
	case pasteFileAction:
		pasteFileHandler(conn, head)
		return
	case copyAction:
		copyHandler(conn, head)
		return
	case downloadAction:
		downloadHandler(conn, head)
		return
	default:
		respError(conn, "unknown action:"+head.Action)
		logrus.Error("unknown action:", head.Action)
		return
	}

}

func pasteTextHandler(conn net.Conn, head headInfo) {
	var bodyBuf = make([]byte, head.DataLen)
	_, err := io.ReadFull(conn, bodyBuf)
	if err != nil {
		logrus.Error("read body error: ", err)
		return
	}
	clipboard.Write(clipboard.FmtText, bodyBuf)

	go func() {
		time.Sleep(time.Millisecond * 200)
		sendMsg(conn, "粘贴成功")
	}()

	contentRune := []rune(string(bodyBuf))
	showLen := 80
	if len(contentRune) >= showLen {
		Inform(string(contentRune[:showLen]) + "...")
	} else {
		Inform(string(contentRune))
	}

}

func pingHandler(conn net.Conn, head headInfo) {
	var bodyBuf = make([]byte, head.DataLen)
	_, err := io.ReadFull(conn, bodyBuf)
	if err != nil {
		logrus.Error("read body error: ", err)
		return
	}
	decryptedBody, err := crypter.Decrypt(bodyBuf)
	if err != nil {
		logrus.Error("decrypt body error: ", err)
		return
	}
	if string(decryptedBody) != "ping" {
		logrus.Error("invalid ping data: ", string(decryptedBody))
		respError(conn, ErrorInvalidData)
		return
	}
	resp := "pong"
	encryptedResp, err := crypter.Encrypt([]byte(resp))
	if err != nil {
		logrus.Error("encrypt body error: ", err)
		return
	}
	// encryptedResp = []byte("pong")
	sendMsgWithBody(conn, "验证成功", DataTypeText, encryptedResp)
}

func commonAuth(conn net.Conn) (headInfo, bool) {
	const headBufSize = 1024
	var headBuf [headBufSize]byte
	var head headInfo

	// 读取json长度
	var headLen int32
	if _, err := io.ReadFull(conn, headBuf[:4]); err != nil {
		return head, false
	}
	headLen = int32(binary.LittleEndian.Uint32(headBuf[:4]))
	if headLen > headBufSize || headLen <= 0 {
		respError(conn, fmt.Sprintf("invalid head len:%d", headLen))
		return head, false
	}
	// 读取json
	if _, err := io.ReadFull(conn, headBuf[:headLen]); err != nil {
		logrus.Error("read head failed, err:", err)
		return head, false
	}

	if err := json.Unmarshal(headBuf[:headLen], &head); err != nil {
		logrus.Error("json unmarshal failed, err:", err)
		return head, false
	}
	if head.TimeIp == "" {
		respError(conn, "time-ip is empty")
		return head, false
	}
	timeAndIPBytes, err := hex.DecodeString(head.TimeIp)
	if err != nil {
		respError(conn, err.Error())
		return head, false
	}
	decrypted, err := crypter.Decrypt(timeAndIPBytes)
	if err != nil {
		respError(conn, err.Error())
		return head, false
	}
	// 2006-01-02 15:04:05
	timeAndIPStr := string(decrypted)
	timeLen := len(TimeFormat)
	if len(timeAndIPStr) < timeLen {
		respError(conn, "time-ip is too short")
		return head, false
	}
	timeStr := timeAndIPStr[:timeLen]
	ip := timeAndIPStr[timeLen+1:]
	t, err := time.Parse(TimeFormat, timeStr)
	if err != nil {
		respError(conn, err.Error())
		return head, false
	}
	if time.Since(t).Seconds() > MaxTimeDiff {
		logrus.Info("time expired: ", t.String())
		respError(conn, fmt.Sprintf("time expired: %s", t.String()))
		return head, false
	}

	var myipv4 string
	if strings.Contains(conn.LocalAddr().String(), ":") {
		myipv4 = strings.Split(conn.LocalAddr().String(), ":")[0]
	} else {
		myipv4 = conn.LocalAddr().String()
	}
	if ip != myipv4 {
		logrus.Info("ip not match: ", ip, myipv4)
		respError(conn, fmt.Sprintf("ip not match: %s != %s", ip, myipv4))
		return head, false
	}
	return head, true
}

func copyHandler(conn net.Conn, head headInfo) {

	// 用户选择的文件
	if len(SelectedFiles) != 0 {
		err := sendFiles(conn)
		if err != nil {
			logrus.Error("send files error: ", err)
		} else {
			clearFilesCH <- struct{}{}
		}
		return
	}

	// 空剪切板
	if clipboarDataType == clipboardWatchDataEmpty {
		respError(conn, ErrorClipboardDataEmpty)
		return
	}

	// 文本剪切板
	if clipboarDataType == clipboardWatchDataTypeText {
		sendText(conn)
		return
	}

	// 图片剪切板
	if clipboarDataType == clipboardWatchDataTypeImage {
		sendImage(conn)
		return
	}
}

func sendFiles(conn net.Conn) error {
	var resp RespHead
	resp.Code = 200
	resp.DataType = DataTypeFilePaths
	// resp.Paths = SelectedFiles
	for _, path := range SelectedFiles {
		fileInfo, err := os.Stat(path)
		if err != nil {
			logrus.Error("stat file error: ", err)
			return err
		}
		var pi pathInfo
		pi.Path = path
		pi.Size = fileInfo.Size()
		resp.Paths = append(resp.Paths, pi)
	}
	return sendHead(conn, resp)
}

func sendImage(conn net.Conn) {
	imageName := time.Now().Format("20060102150405") + ".png"
	sendMsgWithBody(conn, imageName, DataTypeClipImage, clipboardWatchData)
}

func sendText(conn net.Conn) {
	sendMsgWithBody(conn, "", DataTypeText, clipboardWatchData)
}

func respError(conn net.Conn, msg string) {
	var resp RespHead
	resp.Code = 400
	resp.Msg = msg
	respBuf, err := json.Marshal(resp)
	if err != nil {
		logrus.Error("json marshal failed, err:", err)
		return
	}
	var headLen = len(respBuf)
	var headLenBuf [4]byte
	binary.LittleEndian.PutUint32(headLenBuf[:], uint32(headLen))
	if _, err := conn.Write(headLenBuf[:]); err != nil {
		logrus.Error("write head len failed, err:", err)
		return
	}
	if _, err := conn.Write(respBuf); err != nil {
		logrus.Error("write head failed, err:", err)
		return
	}
}

func sendMsg(conn net.Conn, msg string) error {
	var resp RespHead
	resp.Code = 200
	resp.Msg = msg
	return sendHead(conn, resp)
}

func sendHead(conn net.Conn, head RespHead) error {
	respBuf, err := json.Marshal(head)
	if err != nil {
		logrus.Error("json marshal failed, err:", err)
		return err
	}
	// logrus.Debugln("respHead:", string(respBuf))
	logrus.Debugln("respHead:", head)
	var headLen = len(respBuf)

	var headLenBuf [4]byte
	binary.LittleEndian.PutUint32(headLenBuf[:], uint32(headLen))
	if _, err := conn.Write(headLenBuf[:]); err != nil {
		logrus.Error("write head len failed, err:", err)
		return err
	}
	if _, err := conn.Write(respBuf); err != nil {
		logrus.Error("write head failed, err:", err)
		return err
	}
	return nil
}

func sendMsgWithBody(conn net.Conn, msg string, datatype string, body []byte) {
	var resp RespHead
	resp.Code = 200
	resp.Msg = msg
	resp.DataType = datatype
	resp.DataLen = int64(len(body))
	respBuf, err := json.Marshal(resp)
	if err != nil {
		logrus.Error("json marshal failed, err:", err)
		return
	}
	var headLen = len(respBuf)
	// fmt.Println("headLen:", headLen, "head:", string(respBuf))
	var headLenBuf [4]byte
	binary.LittleEndian.PutUint32(headLenBuf[:], uint32(headLen))
	if _, err := conn.Write(headLenBuf[:]); err != nil {
		logrus.Error("write head len failed, err:", err)
		return
	}
	if _, err := conn.Write(respBuf); err != nil {
		logrus.Error("write head failed, err:", err)
		return
	}
	if _, err := conn.Write(body); err != nil {
		logrus.Error("write body failed, err:", err)
		return
	}
}
