package main

import (
	"crypto/tls"
	"runtime"

	"github.com/sirupsen/logrus"
)

var crypter *CbcAESCrypt

const ProgramName = "clipboard-go"
const ProgramUrl = "https://github.com/Doraemonkeys/clipboard-go"

func init() {
	InitGlobalLogger()
	cnf := initGlobalConfig()
	var err error
	crypter, err = NewAESCryptFromHex(cnf.SecretKeyHex)
	if err != nil {
		logrus.Panic(err)
	}
	err = InitMyUrl(cnf.SecretKeyHex)
	if err != nil {
		logrus.Panic(err)
	}
	InitTSLConfig()
}

func main() {
	runtime.UnlockOSThread()
	go clipboardWatcher()
	var quitCh = make(chan bool)
	if GloballCnf.ShowToolbarIcon {
		quitCh = ShowStatusBar()
	}

	go runRoute()

	for {
		q := <-quitCh
		if q {
			logrus.Info("program quit...")
			break
		}
		logrus.Info("the status bar icon is hidden")
	}
}

func runRoute() {
	listener, err := tls.Listen("tcp", ":"+GloballCnf.ServerPort, GetTSLConfig())
	if err != nil {
		logrus.Panic(err)
		return
	}
	defer listener.Close()
	for {
		conn, err := listener.Accept()
		if err != nil {
			logrus.Error("accept error:", err)
			continue
		}
		go mainProcess(conn)
	}
}
