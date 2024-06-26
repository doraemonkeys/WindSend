package main

import (
	"crypto/tls"
	"net"
	"runtime"

	"github.com/sirupsen/logrus"
)

var crypter *CbcAESCrypt

const ProgramName = "WindSend-S-Go"
const ProgramUrl = "https://github.com/doraemonkeys/WindSend"
const ProgramVersion = "1.3.0"

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
	if GloballCnf.ShowSystrayIcon {
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
	defer func(listener net.Listener) {
		_ = listener.Close()
	}(listener)
	for {
		conn, err := listener.Accept()
		if err != nil {
			logrus.Error("accept error:", err)
			continue
		}
		go mainProcess(conn)
	}
}
