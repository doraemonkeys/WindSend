package main

import (
	"encoding/hex"
	"fmt"
	"io"
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

const TimeFormat = "2006-01-02 15:04:05"

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
)

func commonAuth(c *gin.Context) bool {
	token := c.GetHeader("token")
	secretKeyHexHash, err := GetSha256([]byte(GloballCnf.SecretKeyHex))
	if err != nil {
		logrus.Error("get sha256 error: ", err)
		c.String(500, ErrorInternal+": "+err.Error())
		return false
	}
	secretKeyHexHashHex := hex.EncodeToString(secretKeyHexHash)
	if token != secretKeyHexHashHex {
		c.String(401, ErrorInvalidAuthData)
		return false
	}
	return true
}

func sendFiles(c *gin.Context) error {
	c.Header("data-type", "files")
	c.Header("file-count", fmt.Sprintf("%d", len(SelectedFiles)))
	//c.Header("Content-Type", "application/octet-stream")
	if len(SelectedFiles) == 1 {
		fileName := filepath.Base(SelectedFiles[0])
		c.Writer.Header().Add("file-name", fileName)
		c.File(SelectedFiles[0])
		return nil
	}
	// 多个文件
	body := strings.Join(SelectedFiles, "\n")
	c.String(200, body)
	return nil
}

func downloadHandler(c *gin.Context) {
	// 身份验证
	ok := commonAuth(c)
	if !ok {
		return
	}
	// filePath 在body中
	filePath, err := io.ReadAll(c.Request.Body)
	if err != nil {
		logrus.Error("read body error: ", err)
		c.String(500, ErrorInternal+": "+err.Error())
		return
	}
	c.File(string(filePath))
}

func copyHandler(c *gin.Context) {
	// 身份验证
	ok := commonAuth(c)
	if !ok {
		return
	}

	// 用户选择的文件
	if len(SelectedFiles) != 0 {
		err := sendFiles(c)
		if err != nil {
			logrus.Error("send files error: ", err)
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
	c.Header("data-type", "text")
	c.String(200, string(clipboardWatchData))
}

func sendImage(c *gin.Context) {
	c.Header("data-type", "files")
	c.Header("file-count", "1")
	name := time.Now().Format("20060102150405") + ".png"
	c.Writer.Header().Add("file-name", name)
	c.Writer.Header().Add("Content-Type", "application/octet-stream")
	c.Writer.Write(clipboardWatchData)
	c.Status(200)
}
func pasteHandler(c *gin.Context) {
	ok := commonAuth(c)
	if !ok {
		return
	}
	// 读取数据类型
	dataType := c.GetHeader("data-type")
	if dataType == "text" {
		pasteText(c)
		return
	}
	if dataType == "files" {
		pasteFiles(c)
		return
	}
}

func pasteFiles(c *gin.Context) {
	forms, err := c.MultipartForm()
	if err != nil {
		logrus.Error("get multipart form error: ", err)
		c.String(500, ErrorInternal+": "+err.Error())
		return
	}
	files := forms.File["files"]
	if len(files) == 0 {
		c.String(500, ErrorInvalidData)
		return
	}
	for _, file := range files {
		err := c.SaveUploadedFile(file, filepath.Join(GloballCnf.SavePath, file.Filename))
		if err != nil {
			logrus.Error("save uploaded file error: ", err)
			c.String(500, ErrorInternal+": "+err.Error())
			return
		}
	}
	Inform(fmt.Sprintf("%d个文件已保存到%s", len(files), GloballCnf.SavePath))
	c.String(200, "更新成功")
}

func pasteText(c *gin.Context) {
	content, err := io.ReadAll(c.Request.Body)
	if err != nil {
		logrus.Error("read body error: ", err)
		c.String(500, ErrorInternal+": "+err.Error())
		return
	}
	clipboard.Write(clipboard.FmtText, content)
	if len(content[1:]) >= 100 {
		Inform(string(content[:99]) + "...")
	} else {
		Inform(string(content[:]))
	}
	c.String(200, "更新成功")
}

func pingHandler(c *gin.Context) {
	body, err := io.ReadAll(c.Request.Body)
	if err != nil {
		logrus.Error("read body error: ", err)
		c.String(500, ErrorInternal+": "+err.Error())
		return
	}
	decryptedBody, err := crypter.Decrypt(body)
	if err != nil {
		logrus.Error("decrypt body error: ", err)
		c.String(400, ErrorInvalidData)
		return
	}
	if string(decryptedBody) != "ping" {
		c.String(400, ErrorInvalidData)
		return
	}
	resp := "pong"
	encryptedResp, err := crypter.Encrypt([]byte(resp))
	if err != nil {
		logrus.Error("encrypt body error: ", err)
		c.String(500, ErrorInternal+": "+err.Error())
		return
	}
	// encryptedResp = []byte("pong")
	c.String(200, string(encryptedResp))
}

// 404
func notFoundHandler(c *gin.Context) {
	c.String(404, "Sorry, I don't know what you're asking for :(")
}
