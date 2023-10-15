package main

import (
	"bytes"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"net/http/cookiejar"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/harry1453/go-common-file-dialog/cfd"
	"github.com/wumansgy/goEncrypt/aes"
	"golang.org/x/net/publicsuffix"
	"golang.org/x/text/encoding/simplifiedchinese"
	"golang.org/x/text/transform"
)

type CbcAESCrypt struct {
	// contains filtered or unexported fields
	secretKey []byte
}

// NewAESCryptFromHex 创建AES加密器, HexSecretKey为16进制字符串
// CBC模式，PKCS5填充
func NewAESCryptFromHex(HexSecretKey string) (*CbcAESCrypt, error) {
	// 128, 192, or 256 bits
	if len(HexSecretKey) != 32 && len(HexSecretKey) != 48 && len(HexSecretKey) != 64 {
		return nil, errors.New("HexSecretKey length must be 32, 48 or 64")
	}
	secretKey, err := hex.DecodeString(HexSecretKey)
	return &CbcAESCrypt{secretKey: secretKey}, err
}

// NewAESCryptFromHex 创建AES加密器, HexSecretKey为16进制字符串。
// 第三方库使用 CBC模式，PKCS5填充。
func NewAESCrypt(SecretKey []byte) (*CbcAESCrypt, error) {
	// 128, 192, or 256 bits
	if len(SecretKey) != 16 && len(SecretKey) != 24 && len(SecretKey) != 32 {
		return nil, errors.New("SecretKey length must be 16, 24 or 32")
	}
	return &CbcAESCrypt{secretKey: SecretKey}, nil
}

// Encrypt 加密后返回 密文+16字节IV。
func (a *CbcAESCrypt) Encrypt(plainText []byte) ([]byte, error) {
	if len(plainText) == 0 {
		return nil, errors.New("plainText is empty")
	}
	IV := a.rand16Byte()
	rawCipherTextHex, err := aes.AesCbcEncrypt(plainText, a.secretKey, IV)
	if err != nil {
		return nil, err
	}
	rawCipherTextHex = append(rawCipherTextHex, IV...)
	return rawCipherTextHex, nil
}

// Decrypt 解密，cipherText 为 密文+16字节IV。
func (a *CbcAESCrypt) Decrypt(cipherText []byte) ([]byte, error) {
	if len(cipherText) <= 16 {
		return nil, errors.New("cipherTextHex length must be greater than 16")
	}
	IV := cipherText[len(cipherText)-16:]
	cipherText = cipherText[:len(cipherText)-16]
	return aes.AesCbcDecrypt(cipherText, a.secretKey, IV)
}

func (a *CbcAESCrypt) rand16Byte() []byte {
	return randNByte(16)
}

// randNByte returns a slice of n random bytes.
func randNByte(n int) []byte {
	b := make([]byte, n)
	rand.Read(b)
	return b
}

func OpenUrl(uri string) error {
	switch runtime.GOOS {
	case "windows":
		cmd := exec.Command("cmd", "/c", "start", uri)
		return cmd.Start()
	case "darwin":
		cmd := exec.Command("open", uri)
		return cmd.Start()
	case "linux":
		cmd := exec.Command("xdg-open", uri)
		return cmd.Start()
	default:
		return fmt.Errorf("don't know how to open things on %s platform", runtime.GOOS)
	}
}

type StartHelper struct {
	// 可执行文件名称
	ExeName string
}

// 文件或文件夹是否存在
func FileOrDirIsExist(path string) bool {
	_, err := os.Stat(path)
	return err == nil || os.IsExist(err)
}

func NewStartHelper(exeName string) *StartHelper {
	return &StartHelper{ExeName: exeName}
}

// GBK is the GBK encoding. It encodes an extension of the GB2312 character set
// and is also known as Code Page 936.
func UTF8ToGBK(b []byte) []byte {
	tfr := transform.NewReader(bytes.NewReader(b), simplifiedchinese.GBK.NewEncoder())
	d, e := io.ReadAll(tfr)
	if e != nil {
		return nil
	}
	return d
}

func (s *StartHelper) SetAutoStart() error {
	if runtime.GOOS == "darwin" {
		return s.setMacAutoStart()
	}
	if runtime.GOOS != "windows" {
		return fmt.Errorf("不支持的操作系统: %v", runtime.GOOS)
	}
	// C:\Users\*\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup
	// 获取当前Windows用户的home directory.
	winUserHomeDir, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("获取当前Windows用户的home directory失败: %v", err)
	}
	startFile := winUserHomeDir + `\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup` +
		`\` + s.ExeName + `_start.vbs`

	path, err := os.Getwd()
	if err != nil {
		return fmt.Errorf("获取当前文件目录失败: %v", err)
	}
	path = strings.Replace(path, `\`, `\\`, -1)

	var content string
	content += `Set objShell = CreateObject("WScript.Shell")` + "\r\n"
	content += `objShell.CurrentDirectory = "` + path + `"` + "\r\n"
	content += `objShell.Run "powershell /c ` + ".\\" + s.ExeName + `"` + `,0`
	contentBytes := UTF8ToGBK([]byte(content))
	oldContent, err := os.ReadFile(startFile)
	if err == nil && bytes.Equal(oldContent, contentBytes) {
		return nil
	}
	file, err := os.OpenFile(startFile, os.O_CREATE|os.O_TRUNC|os.O_RDWR, 0666)
	if err != nil {
		return fmt.Errorf("创建文件失败: %v", err)
	}
	defer file.Close()
	_, err = file.Write(contentBytes)
	if err != nil {
		return fmt.Errorf("写入文件失败: %v", err)
	}
	return nil
}

func (s *StartHelper) UnSetAutoStart() error {
	if runtime.GOOS == "darwin" {
		return s.unSetMacAutoStart()
	}
	winUserHomeDir, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("获取当前Windows用户的home directory失败: %v", err)
	}
	startFile := winUserHomeDir + `\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup` +
		`\` + s.ExeName + `_start.vbs`

	if !FileOrDirIsExist(startFile) {
		return nil
	}

	err = os.Remove(startFile)
	if err != nil {
		return fmt.Errorf("删除文件失败: %v", err)
	}
	return nil
}

func (s *StartHelper) setMacAutoStart() error {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("获取当前用户的home directory失败: %v", err)
	}
	startFile := homeDir + `/Library/LaunchAgents/` + s.ExeName + `_start.plist`
	curPath, err := os.Getwd()
	if err != nil {
		return fmt.Errorf("获取当前文件目录失败: %v", err)
	}
	macListFile := `
	<?xml version="1.0" encoding="UTF-8"?>
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
	<plist version="1.0">
	<dict>
		<key>Label</key>
		<string>` + s.ExeName + `_start</string>
		<key>ProgramArguments</key>
			<array>
				<string>` + curPath + `/` + s.ExeName + `</string>
			</array>
		<key>RunAtLoad</key>
		<true/>
		<key>WorkingDirectory</key>
		<string>/Applications/DownTip.app/Contents/MacOS</string>
		<key>StandardErrorPath</key>
		<string>/tmp/` + s.ExeName + `_start.err</string>
		<key>StandardOutPath</key>
		<string>/tmp/` + s.ExeName + `_start.out</string>
	</dict>
	</plist>
	`
	oldContent, err := os.ReadFile(startFile)
	if err == nil && bytes.Equal(oldContent, []byte(macListFile)) {
		return nil
	}
	file, err := os.OpenFile(startFile, os.O_CREATE|os.O_TRUNC|os.O_RDWR, 0666)
	if err != nil {
		return fmt.Errorf("创建文件失败: %v", err)
	}
	defer file.Close()
	_, err = file.Write([]byte(macListFile))
	if err != nil {
		return fmt.Errorf("写入文件失败: %v", err)
	}
	return nil
}

func (s *StartHelper) unSetMacAutoStart() error {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("获取当前用户的home directory失败: %v", err)
	}
	startFile := homeDir + `/Library/LaunchAgents/` + s.ExeName + `_start.plist`
	if !FileOrDirIsExist(startFile) {
		return nil
	}
	err = os.Remove(startFile)
	if err != nil {
		return fmt.Errorf("删除文件失败: %v", err)
	}
	return nil
}

// 返回选择的文件路径(绝对路径)
func SelectMultiFilesOnWindows(role string) ([]string, error) {
	openMultiDialog, err := cfd.NewOpenMultipleFilesDialog(cfd.DialogConfig{
		Title: "Select Multiple Files",
		Role:  role,
		FileFilters: []cfd.FileFilter{
			{
				DisplayName: "Text Files (*.txt)",
				Pattern:     "*.txt",
			},
			{
				DisplayName: "Image Files (*.jpg, *.png)",
				Pattern:     "*.jpg;*.png",
			},
			{
				DisplayName: "All Files (*.*)",
				Pattern:     "*.*",
			},
		},
		SelectedFileFilterIndex: 2,
	})
	if err != nil {
		return nil, err
	}
	if err := openMultiDialog.Show(); err != nil {
		return nil, err
	}
	return openMultiDialog.GetResults()
}

// 获取系统默认桌面路径
func GetDesktopPath() (string, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	desktopPath := filepath.Join(homeDir, "Desktop")
	if _, err := os.Stat(desktopPath); os.IsNotExist(err) {
		return "", fmt.Errorf("desktop path not exist")
	}
	return desktopPath, nil
}

// 选择文件夹(仅限windows)
func SelectFolderOnWindows(role string) (string, error) {
	pickFolderDialog, err := cfd.NewSelectFolderDialog(cfd.DialogConfig{
		Title: "Pick Folder",
		Role:  role,
	})
	if err != nil {
		return "", err
	}
	if err := pickFolderDialog.Show(); err != nil {
		return "", err
	}
	return pickFolderDialog.GetResult()
}

// 计算sha256
func GetSha256(content []byte) ([]byte, error) {
	hash := sha256.New()
	_, err := hash.Write(content)
	if err != nil {
		return nil, err
	}
	return hash.Sum(nil), nil
}
func Get_client() (http.Client, error) {
	jar, _ := cookiejar.New(&cookiejar.Options{PublicSuffixList: publicsuffix.List})
	return http.Client{Jar: jar}, nil
}

// 仅在有写入时才创建文件
type LazyFileWriter struct {
	filePath string
	file     *os.File
}

func (w *LazyFileWriter) Write(p []byte) (n int, err error) {
	if w.file == nil {
		w.file, err = os.OpenFile(w.filePath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		if err != nil {
			return 0, err
		}
	}
	return w.file.Write(p)
}

func (w *LazyFileWriter) Close() error {
	if w.file != nil {
		return w.file.Close()
	}
	return nil
}

func (w *LazyFileWriter) Seek(offset int64, whence int) (int64, error) {
	if w.file == nil {
		return 0, errors.New("file not created")
	}
	return w.file.Seek(offset, whence)
}

// Name returns the name of the file as presented to Open.
func (w *LazyFileWriter) Name() string {
	if w.file != nil {
		return w.file.Name()
	}
	return filepath.Base(w.filePath)
}

// 是否已经创建了文件
func (w *LazyFileWriter) IsCreated() bool {
	return w.file != nil
}

func NewLazyFileWriter(filePath string) *LazyFileWriter {
	return &LazyFileWriter{filePath: filePath}
}

func NewLazyFileWriterWithFile(filePath string, file *os.File) *LazyFileWriter {
	return &LazyFileWriter{filePath: filePath, file: file}
}

func HasImageExt(name string) bool {
	imageExts := []string{".png", ".jpg", ".jpeg", ".gif", ".bmp"}
	for _, ext := range imageExts {
		if strings.HasSuffix(name, ext) {
			return true
		}
	}
	return false
}

// 产生不冲突的文件路径
func generateUniqueFilepath(filePath string) string {
	if _, err := os.Stat(filePath); err != nil {
		return filePath
	}
	dir := filepath.Dir(filePath)
	name := filepath.Base(filePath)
	fileExt := filepath.Ext(name)
	name = name[:len(name)-len(fileExt)]
	for i := 1; ; i++ {
		if fileExt != "" {
			filePath = filepath.Join(dir, fmt.Sprintf("%s(%d)%s", name, i, fileExt))
		} else {
			filePath = filepath.Join(dir, fmt.Sprintf("%s(%d)", name, i))
		}
		if _, err := os.Stat(filePath); err != nil {
			return filePath
		}
	}
}

func GenerateKeyPair() (rawCert, rawKey []byte, err error) {
	// Create private key and self-signed certificate
	// Adapted from https://golang.org/src/crypto/tls/generate_cert.go

	priv, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return
	}
	validFor := time.Hour * 24 * 365 * 10 // ten years
	notBefore := time.Now()
	notAfter := notBefore.Add(validFor)
	serialNumberLimit := new(big.Int).Lsh(big.NewInt(1), 128)
	serialNumber, _ := rand.Int(rand.Reader, serialNumberLimit)
	template := x509.Certificate{
		SerialNumber: serialNumber,
		Subject: pkix.Name{
			Organization: []string{"doraemon"},
		},
		NotBefore: notBefore,
		NotAfter:  notAfter,

		KeyUsage:              x509.KeyUsageKeyEncipherment | x509.KeyUsageDigitalSignature,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
	}
	derBytes, err := x509.CreateCertificate(rand.Reader, &template, &template, &priv.PublicKey, priv)
	if err != nil {
		return
	}

	rawCert = pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: derBytes})
	rawKey = pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(priv)})

	return
}

func hasSpecificExtNames(name string, extNames ...string) bool {
	for _, extName := range extNames {
		if strings.HasSuffix(name, extName) {
			return true
		}
	}
	return false
}
