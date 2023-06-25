package main

import (
	"encoding/hex"
	"fmt"
	"os"

	"github.com/Doraemonkeys/mylog"
	"github.com/sirupsen/logrus"
	"gopkg.in/yaml.v3"
)

type Config struct {
	ServerPort      string `yaml:"serverPort"`
	SecretKeyHex    string `yaml:"secretKeyHex"`
	ShowToolbarIcon bool   `yaml:"showToolbarIcon"`
	// 自启动
	AutoStart bool `yaml:"autoStart"`
	// 文件保存路径
	SavePath string `yaml:"savePath"`
}

var configFilePath string = "config.yaml"
var GloballCnf *Config
var startHelper *StartHelper

func initGlobalConfig() Config {
	startHelper = NewStartHelper(ProgramName)

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
	defer file.Close()
	decoder := yaml.NewDecoder(file)
	err = decoder.Decode(&GloballCnf)
	if err != nil {
		logrus.Panic(err)
	}
	err = GloballCnf.Set()
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
	return err
}

func generateDefaultConfig() Config {
	var cnf Config
	cnf.ServerPort = "6777"
	cnf.SecretKeyHex = generateSecretKeyHex(32)
	cnf.ShowToolbarIcon = true
	cnf.AutoStart = true
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
	defer file.Close()
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
	err := mylog.InitGlobalLogger(logCnf)
	if err != nil {
		panic(err)
	}
}
