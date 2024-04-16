package main

import (
	"crypto/tls"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/doraemonkeys/WindSend/language"
	"github.com/doraemonkeys/mylog"
	"github.com/sirupsen/logrus"
	"gopkg.in/yaml.v3"
)

type Config struct {
	ServerPort      string `yaml:"serverPort"`
	SecretKeyHex    string `yaml:"secretKeyHex"`
	ShowSystrayIcon bool   `yaml:"showToolbarIcon"`
	// 自启动
	AutoStart bool `yaml:"autoStart"`
	// 文件保存路径
	SavePath string `yaml:"savePath"`
	Language string `yaml:"language"`
	// 外部IP
	ExternalIPs []string `yaml:"externalIPs"`
}

var configFilePath = "config.yaml"
var GloballCnf *Config
var startHelper *StartHelper
var AppIconPath string

const AppIconName = "icon-192.png"

func initGlobalConfig() Config {
	curPath, err := os.Getwd()
	if err == nil {
		AppIconPath = filepath.Join(curPath, AppIconName)
	}

	startHelper = NewStartHelper(ProgramName)

	defer func() {
		if err := GloballCnf.Set(); err != nil {
			logrus.Panic(err)
		}
	}()
	if _, err := os.Stat(configFilePath); err != nil {
		cnf := generateDefaultConfig()
		GloballCnf = &cnf
		err := GloballCnf.SaveAndSet()
		if err != nil {
			logrus.Panic(err)
		}
		return *GloballCnf
	}
	file, err := os.Open(configFilePath)
	if err != nil {
		logrus.Panic(err)
	}
	defer func(file *os.File) {
		_ = file.Close()
	}(file)
	decoder := yaml.NewDecoder(file)
	err = decoder.Decode(&GloballCnf)
	if err != nil {
		logrus.Panic(err)
	}
	return *GloballCnf
}

func (cnf Config) EmptyCheck() error {
	if cnf.ServerPort == "" {
		return fmt.Errorf("serverPort is empty")
	}
	if cnf.SecretKeyHex == "" {
		return fmt.Errorf("secretKeyHex is empty")
	}
	return nil
}
func (cnf Config) SaveAndSet() error {
	err := cnf.EmptyCheck()
	if err != nil {
		return err
	}
	if cnf.AutoStart {
		err = startHelper.SetAutoStart()
	} else {
		err = startHelper.UnSetAutoStart()
	}
	if err != nil {
		return err
	}
	return saveConfig(configFilePath, cnf)
}
func (cnf Config) Save() error {
	err := cnf.EmptyCheck()
	if err != nil {
		return err
	}
	return saveConfig(configFilePath, cnf)
}

func (cnf Config) Set() error {
	err := cnf.EmptyCheck()
	if err != nil {
		return err
	}
	if cnf.AutoStart {
		err = startHelper.SetAutoStart()
	} else {
		err = startHelper.UnSetAutoStart()
	}
	for _, v := range language.SupportedLanguageCode {
		if strings.HasPrefix(cnf.Language, v) {
			language.SetLanguage(v)
			break
		}
	}
	return err
}

func generateDefaultConfig() Config {
	var cnf Config
	cnf.ServerPort = "6779"
	cnf.SecretKeyHex = generateSecretKeyHex(32)
	cnf.ShowSystrayIcon = true
	cnf.AutoStart = false
	cnf.Language = GetSystemLang()
	if cnf.Language == "" {
		cnf.Language = language.ZH_CN_CODE
	}
	cnf.ExternalIPs = []string{"test1", "test2"}
	temp, err := GetDesktopPath()
	if err != nil {
		logrus.Error("GetDesktopPath error:", err)
		temp = "./"
	}
	cnf.SavePath = temp
	return cnf
}

func saveConfig(path string, cnf Config) error {
	file, err := os.Create(path)
	if err != nil {
		return err
	}
	defer func(file *os.File) {
		_ = file.Close()
	}(file)
	yamlData, err := yaml.Marshal(cnf)
	if err != nil {
		return err
	}
	_, err = file.Write(yamlData)
	return err
}

func generateSecretKeyHex(byteLen int) string {
	secretKey := randNByte(byteLen)
	return hex.EncodeToString(secretKey)
}

func InitGlobalLogger() {
	var logCnf = mylog.LogConfig{}
	logCnf.MaxLogSize = 1024 * 1024 * 10
	logCnf.MaxKeepDays = 100
	logCnf.NoConsole = true
	logCnf.DisableWriterBuffer = true
	logCnf.LogLevel = mylog.InfoLevel
	err := mylog.InitGlobalLogger(logCnf)
	if err != nil {
		panic(err)
	}
}

const certFile = "./tls/cert.pem"
const keyFile = "./tls/key.pem"

func InitTSLConfig() {
	// mkdir tls
	if !FileOrDirIsExist("./tls") {
		err := os.Mkdir("./tls", os.ModePerm)
		if err != nil {
			logrus.Panic(err)
		}
	}
	// check file
	if !FileOrDirIsExist(certFile) || !FileOrDirIsExist(keyFile) {
		rawCert, rawKey, err := GenerateKeyPair()
		if err != nil {
			logrus.Panic(err)
		}
		err = os.WriteFile(certFile, rawCert, 0644)
		if err != nil {
			logrus.Panic(err)
		}
		err = os.WriteFile(keyFile, rawKey, 0644)
		if err != nil {
			logrus.Panic(err)
		}
	}
}

func GetTSLConfig() (config *tls.Config) {
	cert, err := tls.LoadX509KeyPair(certFile, keyFile)
	if err != nil {
		logrus.Panic(err)
	}
	config = &tls.Config{
		Certificates: []tls.Certificate{cert},
		// 是否跳过证书验证
		InsecureSkipVerify: true,
		MinVersion:         tls.VersionTLS12,
	}
	return
}
