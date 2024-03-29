package main

import (
	"crypto/tls"
	"runtime"

	"github.com/sirupsen/logrus"
)

var crypter *CbcAESCrypt

const ProgramName = "WindSend-S-Go"
const ProgramUrl = "https://github.com/doraemonkeys/WindSend"
const AboutProgram = `WindSend is a cross-platform clipboard synchronization and file transfer tool, which is easy to use and supports clipboard synchronization and file transfer between different platforms. It is based on the principle of P2P transmission, and the transmission speed is fast and stable. It is a good helper for cross-platform clipboard synchronization and file transfer.`
const ProgramVersion = "1.2.2"

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
