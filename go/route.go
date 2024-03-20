package main

import (
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/doraemonkeys/WindSend/language"
	"github.com/sirupsen/logrus"
	"golang.design/x/clipboard"
)

const TimeFormat = "2006-01-02 15:04:05"

const MaxTimeDiff float64 = 300

const (
	// 服务器内部错误
	ErrorInternal = "internal error"
	// 无效的验证数据
	ErrorInvalidAuthData = "invalid auth data"
	// 过期的验证数据
	ErrorExpiredAuthData = "expired auth data"
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
	matchAction     = "match"
	syncTextAction  = "syncText"
	webIp           = "web"
)

type headInfo struct {
	Action     string       `json:"action"`
	DeviceName string       `json:"deviceName"`
	TimeIp     string       `json:"timeIp"`
	FileID     uint32       `json:"fileID"`
	FileSize   int64        `json:"fileSize"`
	Path       string       `json:"path"`
	UploadType pathInfoType `json:"uploadType"`
	// Name       string `json:"name"`
	Start   int64 `json:"start"`
	End     int64 `json:"end"`
	DataLen int64 `json:"dataLen"`
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
	DataLen int64 `json:"dataLen"`
	// Paths   []pathInfo `json:"paths"`
}

type pathInfo struct {
	// dir or file
	Type     pathInfoType `json:"type"`
	Path     string       `json:"path"`
	SavePath string       `json:"savePath"`
	Size     int64        `json:"size"`
}

type pathInfoType = string

const (
	pathInfoTypeDir  pathInfoType = "dir"
	pathInfoTypeFile pathInfoType = "file"
)

type MatchActionResp struct {
	DeviceName   string `json:"deviceName"`
	SecretKeyHex string `json:"secretKeyHex"`
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
			_, _ = panicWriter.Write([]byte(fmt.Sprintf("%v\n", err)))
			var stackBuf = make([]byte, 1024*1024)
			n := runtime.Stack(stackBuf, false)
			_, _ = panicWriter.Write(stackBuf[:n])
		}
	}()
	logrus.Info("remote addr:", conn.RemoteAddr().String())
	defer conn.Close()

	for {
		head, ok := commonAuth(conn)
		if !ok {
			return
		}

		switch head.Action {
		case pingAction:
			pingHandler(conn, head)
			return
		case pasteTextAction:
			pasteTextHandler(conn, head)
			return
		case pasteFileAction:
			ok = pasteFileHandler(conn, head)
		case copyAction:
			copyHandler(conn)
			return
		case downloadAction:
			ok = downloadHandler(conn, head)
		case matchAction:
			matchHandler(conn)
			return
		case syncTextAction:
			syncTextHandler(conn, head)
		default:
			respCommonError(conn, "unknown action:"+head.Action)
			logrus.Error("unknown action:", head.Action)
			return
		}
		if !ok {
			return
		}
	}
}

func pasteTextHandler(conn net.Conn, head headInfo) {
	var bodyBuf = make([]byte, head.DataLen)
	_, err := io.ReadFull(conn, bodyBuf)
	if err != nil {
		// logrus.Error("read body error: ", err)
		logrus.Errorf("read body error: %v, dataLen:%d, bodyBuf:%s\n", err, head.DataLen, string(bodyBuf))
		logrus.Info("head:", head)
		respCommonError(conn, ErrorIncompleteData+": "+err.Error())
		return
	}
	clipboard.Write(clipboard.FmtText, bodyBuf)

	var completionSignal = make(chan struct{})

	go func() {
		// time.Sleep(time.Millisecond * 100)
		_ = sendMsg(conn, "粘贴成功")
		completionSignal <- struct{}{}
	}()

	contentRune := []rune(string(bodyBuf))
	showLen := 60
	if len(contentRune) >= showLen {
		Inform(string(contentRune[:showLen])+"...", head.DeviceName)
	} else {
		Inform(string(contentRune), head.DeviceName)
	}
	<-completionSignal
}

func syncTextHandler(conn net.Conn, head headInfo) {
	var curClipboardText = make([]byte, 0)
	if clipboarDataType == clipboardWatchDataTypeText {
		curClipboardText = clipboardWatchData
	}
	if head.DataLen > 0 {
		var bodyBuf = make([]byte, head.DataLen)
		_, err := io.ReadFull(conn, bodyBuf)
		if err != nil {
			// logrus.Error("read body error: ", err)
			logrus.Errorf("read body error: %v, dataLen:%d, bodyBuf:%s\n", err, head.DataLen, string(bodyBuf))
			logrus.Info("head:", head)
			respCommonError(conn, ErrorIncompleteData+": "+err.Error())
			return
		}
		clipboard.Write(clipboard.FmtText, bodyBuf)
	}
	var _ = sendMsgWithBody(conn, "SyncSuccess", DataTypeText, curClipboardText)
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
		respCommonError(conn, ErrorInvalidData)
		return
	}
	resp := "pong"
	encryptedResp, err := crypter.Encrypt([]byte(resp))
	if err != nil {
		logrus.Error("encrypt body error: ", err)
		return
	}
	// encryptedResp = []byte("pong")
	_ = sendMsgWithBody(conn, language.Translate(language.VerifySuccess), DataTypeText, encryptedResp)
}

func readHead(conn net.Conn) (headInfo, error) {
	var headBuf = make([]byte, 4)
	var head headInfo

	// 读取json长度
	var headLen int32
	if _, err := io.ReadFull(conn, headBuf[:4]); err != nil {
		return head, err
	}
	headLen = int32(binary.LittleEndian.Uint32(headBuf[:4]))
	// 头部不能超过10KB，以防止恶意攻击导致内存溢出
	const maxHeadLen = 1024 * 10
	if headLen > maxHeadLen {
		return head, fmt.Errorf("head len too large: %d", headLen)
	}
	headBuf = make([]byte, headLen)
	// 读取json
	if _, err := io.ReadFull(conn, headBuf[:headLen]); err != nil {
		logrus.Error("read head failed, err:", err)
		return head, err
	}

	if err := json.Unmarshal(headBuf[:headLen], &head); err != nil {
		logrus.Error("json unmarshal failed, err:", err)
		return head, err
	}
	return head, nil
}

func commonAuth(conn net.Conn) (headInfo, bool) {
	const unauthorizedCode = 401
	logrus.Debugln("commonAuth remote addr:", conn.RemoteAddr().String())

	head, err := readHead(conn)
	if err != nil {
		if errors.Is(err, io.EOF) {
			logrus.Infof("client closed, ip:%s\n", conn.RemoteAddr().String())
		} else {
			respError(conn, unauthorizedCode, err.Error())
			logrus.Error("read head failed, err:", err)
		}
		return head, false
	}
	logrus.Debugf("head: %+v", head)
	if head.Action == matchAction {
		if allowSearch {
			return head, true
		}
		logrus.Infof("search not allowed, deviceName:%s,ip:%s\n", head.DeviceName, conn.RemoteAddr().String())
		respError(conn, unauthorizedCode, "search not allowed")
		return head, false
	}
	if head.TimeIp == "" {
		respError(conn, unauthorizedCode, "time-ip is empty")
		return head, false
	}
	timeAndIPBytes, err := hex.DecodeString(head.TimeIp)
	if err != nil {
		respError(conn, unauthorizedCode, err.Error())
		return head, false
	}
	decrypted, err := crypter.Decrypt(timeAndIPBytes)
	if err != nil {
		respError(conn, unauthorizedCode, err.Error())
		return head, false
	}
	// 2006-01-02 15:04:05
	timeAndIPStr := string(decrypted)
	timeLen := len(TimeFormat)
	if len(timeAndIPStr) < timeLen {
		respError(conn, unauthorizedCode, "time-ip is too short")
		return head, false
	}
	timeStr := timeAndIPStr[:timeLen]
	ip := timeAndIPStr[timeLen+1:]
	t, err := time.Parse(TimeFormat, timeStr)
	if err != nil {
		respError(conn, unauthorizedCode, err.Error())
		return head, false
	}
	if time.Since(t).Seconds() > MaxTimeDiff {
		logrus.Info("time expired: ", t.String())
		respError(conn, unauthorizedCode, "time expired: "+t.String())
		return head, false
	}

	var myip = conn.LocalAddr().String()[0:strings.LastIndex(conn.LocalAddr().String(), ":")]
	if myip[0] == '[' && myip[len(myip)-1] == ']' {
		myip = myip[1 : len(myip)-1] //去掉[]
	}
	if strings.Contains(myip, "%") {
		// ipv6, 去掉%后的作用域id
		myip = myip[0:strings.Index(myip, "%")]
	}
	if strings.Contains(ip, "%") {
		ip = ip[:strings.Index(ip, "%")]
	}
	if ip != myip {
		if len(GloballCnf.ExternalIPs) > 0 {
			for _, v := range GloballCnf.ExternalIPs {
				if v == ip {
					return head, true
				}
			}
		}
		logrus.Infoln("ip not match, received ip:", ip, "my ip:", myip)
		respError(conn, unauthorizedCode, fmt.Sprintf("ip not match: %s != %s", ip, myip))
		return head, false
	}
	return head, true
}

func matchHandler(conn net.Conn) {
	resp := MatchActionResp{
		DeviceName:   GetDeviceName(),
		SecretKeyHex: GloballCnf.SecretKeyHex,
	}
	respBuf, err := json.Marshal(resp)
	if err != nil {
		logrus.Error("json marshal failed, err:", err)
		return
	}
	_ = sendMsg(conn, string(respBuf))
	closeAllowSearchCH <- struct{}{}
}

func copyHandler(conn net.Conn) {

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

	// 文件剪切板
	files, err := clipboardS.Files()
	if err == nil && len(files) != 0 {
		SelectedFiles = files
		err := sendFiles(conn)
		if err != nil {
			logrus.Error("send files error: ", err)
		} else {
			SelectedFiles = nil
			err = clipboardS.Clear()
			if err != nil {
				logrus.Error("clear clipboard error: ", err)
			}
		}
		return
	}

	// 空剪切板
	if clipboarDataType == clipboardWatchDataEmpty {
		respCommonError(conn, language.Translate(language.ClipboardIsEmpty))
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
	// resp.Paths = SelectedFiles
	var respPaths = make([]pathInfo, 0, len(SelectedFiles))
	for _, path1 := range SelectedFiles {
		path1 = strings.ReplaceAll(path1, "\\", "/")
		fInfo, err := os.Stat(path1)
		if err != nil {
			logrus.Error("stat file error: ", err)
			respCommonError(conn, err.Error())
			return err
		}
		var pi pathInfo
		pi.Path = path1
		if !fInfo.IsDir() {
			pi.Type = pathInfoTypeFile
			pi.Size = fInfo.Size()
			respPaths = append(respPaths, pi)
			continue
		} else {
			pi.Type = pathInfoTypeDir
			pi.SavePath = filepath.Base(path1)
			respPaths = append(respPaths, pi)
		}
		// 遍历目录
		err = filepath.Walk(path1, func(path2 string, info os.FileInfo, err error) error {
			if err != nil {
				logrus.Error("walk file error: ", err)
				return err
			}
			path2 = strings.ReplaceAll(path2, "\\", "/")
			var pi pathInfo
			pi.Path = path2
			pi.Type = pathInfoTypeDir
			pi.SavePath = filepath.Join(filepath.Base(path1), strings.TrimPrefix(path2, path1))
			if !info.IsDir() {
				pi.Type = pathInfoTypeFile
				pi.Size = info.Size()
				pi.SavePath = filepath.Dir(pi.SavePath)
			}
			respPaths = append(respPaths, pi)
			return nil
		})
		if err != nil {
			logrus.Error("walk file error: ", err)
			respCommonError(conn, err.Error())
			return err
		}
	}
	body, err := json.Marshal(respPaths)
	if err != nil {
		logrus.Error("json marshal failed, err:", err)
		respCommonError(conn, err.Error())
		return err
	}
	return sendMsgWithBody(conn, "", DataTypeFilePaths, body)
}

func sendImage(conn net.Conn) {
	imageName := time.Now().Format("20060102150405") + ".png"
	_ = sendMsgWithBody(conn, imageName, DataTypeClipImage, clipboardWatchData)
}

func sendText(conn net.Conn) {
	_ = sendMsgWithBody(conn, "", DataTypeText, clipboardWatchData)
}

func respCommonError(conn net.Conn, msg string) (ok bool) {
	return respError(conn, 400, msg)
}

func respError(conn net.Conn, code int, msg string) (ok bool) {
	var resp RespHead
	resp.Code = code
	resp.Msg = msg
	respBuf, err := json.Marshal(resp)
	if err != nil {
		logrus.Error("json marshal failed, err:", err)
		return false
	}
	var headLen = len(respBuf)
	var headLenBuf [4]byte
	binary.LittleEndian.PutUint32(headLenBuf[:], uint32(headLen))
	if _, err := conn.Write(headLenBuf[:]); err != nil {
		logrus.Error("write head len failed, err:", err)
		return false
	}
	if _, err := conn.Write(respBuf); err != nil {
		logrus.Error("write head failed, err:", err)
		return false
	}
	return true
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

func sendMsgWithBody(conn net.Conn, msg string, datatype string, body []byte) error {
	var resp RespHead
	resp.Code = 200
	resp.Msg = msg
	resp.DataType = datatype
	resp.DataLen = int64(len(body))
	respBuf, err := json.Marshal(resp)
	if err != nil {
		logrus.Error("json marshal failed, err:", err)
		return err
	}
	var headLen = len(respBuf)
	// fmt.Println("headLen:", headLen, "head:", string(respBuf))
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
	if _, err := conn.Write(body); err != nil {
		logrus.Error("write body failed, err:", err)
		return err
	}
	return nil
}
