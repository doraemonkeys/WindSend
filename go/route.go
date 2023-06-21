package main

import (
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/sirupsen/logrus"
	"golang.design/x/clipboard"
)

// 剪切板同步工具

// post /copy
// post /paste

// -------+--------+--------+--------+--------+
// 1 byte | 1 byte | 4 byte | n byte | 4 byte |
// -------+--------+--------+--------+--------+
//  type  | number |nameLen |  name  |  data  |

const TimeFormat = "2006-01-02 15:04:05"
const MaxTimeDiff float64 = 10

const MaxAllowedSize = 1024 * 1024 * 50

const (
	// 服务器内部错误
	ErrorInternal = "internal error"
	// 无效的验证数据
	ErrorInvalidAuthData = "invalid auth data"
	// 过期的验证数据
	ErrorExpiredAuthData = "expired auth data"
	// 剪切板数据为空
	ErrorClipboardDataEmpty = "clipboard data empty"
	// 剪切板数据过大
	ErrorClipboardDataTooLarge = "clipboard data too large"
)

var lastRandBytes []byte

func copyAuth(c *gin.Context) {
	// 读取
	encryptedata, err := io.ReadAll(c.Request.Body)
	if err != nil {
		c.String(500, ErrorInternal+": "+err.Error())
		return
	}
	// 解密
	decryptedata, err := crypter.Decrypt(encryptedata)
	if err != nil {
		c.String(500, ErrorInvalidAuthData+": "+err.Error())
		return
	}
	// 验证"2006-01-02 15:04:05" + 32位随机字符串(byte)
	timeLen := len(TimeFormat)
	if len(decryptedata) != 32+len(TimeFormat) {
		c.String(500, ErrorInvalidAuthData)
		return
	}
	if lastRandBytes != nil && string(decryptedata[timeLen:]) == string(lastRandBytes) {
		c.String(500, ErrorInvalidAuthData)
		return
	}

	// 验证时间
	t, err := time.Parse(TimeFormat, string(decryptedata[:timeLen]))
	if err != nil {
		c.String(500, ErrorInvalidAuthData)
		return
	}
	if time.Since(t).Seconds() > MaxTimeDiff {
		c.String(500, ErrorExpiredAuthData)
		return
	}
	lastRandBytes = decryptedata[timeLen:]
}

func sendFiles(c *gin.Context) error {
	// 读取文件
	var rawBody []byte
	bodyType := byte(0x01)
	number := byte(len(SelectedFiles))
	rawBody = append(rawBody, bodyType)
	rawBody = append(rawBody, number)
	for i := 0; i < len(SelectedFiles); i++ {
		name := filepath.Base(SelectedFiles[i])
		var nameLen uint32 = uint32(len(name))
		nameLenBytes := []byte{byte(nameLen >> 24), byte(nameLen >> 16), byte(nameLen >> 8), byte(nameLen)}
		rawBody = append(rawBody, nameLenBytes...)
		rawBody = append(rawBody, []byte(name)...)
		data, err := os.ReadFile(SelectedFiles[i])
		if err != nil {
			c.String(500, ErrorInternal+": "+err.Error())
			return err
		}
		var dataLen uint32 = uint32(len(data))
		dataLenBytes := []byte{byte(dataLen >> 24), byte(dataLen >> 16), byte(dataLen >> 8), byte(dataLen)}
		rawBody = append(rawBody, dataLenBytes...)
		rawBody = append(rawBody, data...)
	}
	encryptedBody, err := crypter.Encrypt(rawBody)
	if err != nil {
		c.String(500, ErrorInternal+": "+err.Error())
		return err
	}
	c.String(200, string(encryptedBody))
	return nil
}

func copyHandler(c *gin.Context) {
	// 身份验证
	copyAuth(c)

	// 文件剪切板
	if len(SelectedFiles) != 0 {
		err := sendFiles(c)
		if err != nil {
			logrus.Error(err)
		} else {
			clearFilesCH <- struct{}{}
		}
		return
	}

	// 空剪切板
	if clipboarDataType == clipboardWatchDataEmpty {
		c.String(500, ErrorClipboardDataEmpty)
		return
	}

	// 文本剪切板
	if clipboarDataType == clipboardWatchDataTypeText {
		sendText(c)
		return
	}

	// 图片剪切板
	if clipboarDataType == clipboardWatchDataTypeImage {
		sendImage(c)
		return
	}
}

func sendText(c *gin.Context) {
	bodyType := []byte{0x00}
	encryptedBody, err := crypter.Encrypt(append(bodyType, clipboardWatchData...))
	if err != nil {
		c.String(500, ErrorInternal+": "+err.Error())
	}
	c.String(200, string(encryptedBody))
}

func sendImage(c *gin.Context) {
	bodyType := []byte{0x01}
	number := []byte{0x01}
	name := time.Now().Format("20060102150405") + ".png"
	var nameLen uint32 = uint32(len(name))
	nameLenBytes := []byte{byte(nameLen >> 24), byte(nameLen >> 16), byte(nameLen >> 8), byte(nameLen)}
	var dataLen uint32 = uint32(len(clipboardWatchData))
	dataLenBytes := []byte{byte(dataLen >> 24), byte(dataLen >> 16), byte(dataLen >> 8), byte(dataLen)}
	rawBody := append(bodyType, number...)
	rawBody = append(rawBody, nameLenBytes...)
	rawBody = append(rawBody, []byte(name)...)
	rawBody = append(rawBody, dataLenBytes...)
	rawBody = append(rawBody, clipboardWatchData...)
	encryptedBody, err := crypter.Encrypt(rawBody)
	if err != nil {
		c.String(500, ErrorInternal+": "+err.Error())
	}
	c.String(200, string(encryptedBody))
}
func pasteHandler(c *gin.Context) {
	encryptedata, err := io.ReadAll(c.Request.Body)
	if err != nil {
		c.String(500, ErrorInternal+": "+err.Error())
		return
	}
	decryptedata, err := crypter.Decrypt(encryptedata)
	if err != nil {
		c.String(500, ErrorInvalidAuthData+": "+err.Error())
		return
	}
	if len(decryptedata) == 0 {
		c.String(500, ErrorInvalidAuthData)
		return
	}
	// 文本
	if decryptedata[0] == 0x00 {
		clipboard.Write(clipboard.FmtText, decryptedata[1:])
		if len(decryptedata[1:]) >= 100 {
			Inform(string(decryptedata[1:99]) + "...")
		} else {
			Inform(string(decryptedata[1:]))
		}
		c.String(200, "更新成功")
		return
	}
	// 文件
	if decryptedata[0] == 0x01 {
		saveFiles(decryptedata[1:])
		Inform("文件已保存")
		c.String(200, "更新成功")
		return
	}
}

func saveFiles(data []byte) {
	number := data[0]
	data = data[1:]
	for i := 0; i < int(number); i++ {
		nameLen := uint32(data[0])<<24 | uint32(data[1])<<16 | uint32(data[2])<<8 | uint32(data[3])
		name := string(data[4 : 4+nameLen])
		data = data[4+nameLen:]
		dataLen := uint32(data[0])<<24 | uint32(data[1])<<16 | uint32(data[2])<<8 | uint32(data[3])
		data = data[4:]
		path := filepath.Join(GloballCnf.SavePath, name)
		err := os.WriteFile(path, data[:dataLen], 0644)
		if err != nil {
			logrus.Error(err)
		}
		// 尝试将图片同步到剪切板(只有一张图片时)
		if number == 1 && hasImageExt(name) {
			// 只支持png
			clipboard.Write(clipboard.FmtImage, data[:dataLen])
		}
		data = data[dataLen:]
	}
}

func hasImageExt(name string) bool {
	imageExts := []string{".png", ".jpg", ".jpeg", ".gif", ".bmp"}
	for _, ext := range imageExts {
		if strings.HasSuffix(name, ext) {
			return true
		}
	}
	return false
}

func pingHandler(c *gin.Context) {
	// TODO: 身份验证
	c.String(200, "pong")
}
