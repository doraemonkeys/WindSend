package main

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"net/http"
	"net/http/cookiejar"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"unsafe"

	"github.com/axgle/mahonia"
	"github.com/lxn/win"
	"github.com/sirupsen/logrus"
	"github.com/wumansgy/goEncrypt/aes"
	"golang.org/x/net/publicsuffix"
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

// GB18030
func Utf8ToANSI(text string) string {
	return mahonia.NewEncoder("GB18030").ConvertString(text)
}

func (s *StartHelper) SetAutoStart() error {
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
	content += `Set objShell = CreateObject("WScript.Shell")` + "\n"
	content += `objShell.CurrentDirectory = "` + path + `"` + "\n"
	content += `objShell.Run "powershell /c ` + ".\\" + s.ExeName + `"` + `,0`
	content = Utf8ToANSI(content)
	oldContent, err := os.ReadFile(startFile)
	if err == nil && string(oldContent) == content {
		return nil
	}
	file, err := os.OpenFile(startFile, os.O_CREATE|os.O_TRUNC|os.O_RDWR, 0666)
	if err != nil {
		return fmt.Errorf("创建文件失败: %v", err)
	}
	defer file.Close()
	_, err = file.WriteString(content)
	if err != nil {
		return fmt.Errorf("写入文件失败: %v", err)
	}
	return nil
}

func (s *StartHelper) UnSetAutoStart() error {
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

// 返回选择的文件路径(绝对路径)
func SelectMultiFilesOnWindows() ([]string, error) {
	var ofn win.OPENFILENAME
	fileNames := make([]uint16, 1024*1024)

	ofn.LStructSize = uint32(unsafe.Sizeof(ofn))
	ofn.Flags = win.OFN_ALLOWMULTISELECT | win.OFN_EXPLORER | win.OFN_LONGNAMES | win.OFN_FILEMUSTEXIST | win.OFN_PATHMUSTEXIST

	ofn.NMaxFile = uint32(len(fileNames))
	ofn.LpstrFile = &fileNames[0]

	ret := win.GetOpenFileName(&ofn)
	if ret {
		return parseMultiString(fileNames), nil
	}
	// 用户取消选择或者选择失败(比如选择了太多文件)
	return nil, fmt.Errorf("user cancel or select too many files")
}

// Helper function to convert the multistring returned by GetOpenFileName to a slice of strings
func parseMultiString(multiString []uint16) []string {
	var ret []string = make([]string, 0)
	for i := 0; i < len(multiString); i++ {
		if multiString[i] != 0 {
			var str []uint16
			for ; i < len(multiString); i++ {
				str = append(str, multiString[i])
				if multiString[i] == 0 {
					break
				}
			}
			ret = append(ret, win.UTF16PtrToString(&str[0]))
		}
	}
	logrus.Debugf("parseMultiString: %v", ret)
	if len(ret) <= 1 {
		return ret
	}
	var dir = ret[0]
	for i := 1; i < len(ret); i++ {
		ret[i] = filepath.Join(dir, ret[i])
	}
	return ret[1:]
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
func SelectFolderOnWindows() (string, error) {
	const BIF_RETURNONLYFSDIRS = 0x00000001
	const BIF_NEWDIALOGSTYLE = 0x00000040
	var bi win.BROWSEINFO
	bi.HwndOwner = win.GetDesktopWindow()
	bi.UlFlags = BIF_RETURNONLYFSDIRS | BIF_NEWDIALOGSTYLE
	bi.LpszTitle, _ = syscall.UTF16PtrFromString("Select a folder")

	id := win.SHBrowseForFolder(&bi)
	if id != 0 {
		path := make([]uint16, win.MAX_PATH)
		win.SHGetPathFromIDList(id, &path[0])
		return syscall.UTF16ToString(path), nil
	}
	return "", fmt.Errorf("user cancel")
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
