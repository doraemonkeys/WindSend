package main

import (
	"runtime"

	"github.com/gin-gonic/gin"
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

// go build -ldflags "-H=windowsgui"
func main() {
	runtime.UnlockOSThread()
	go clipboardWatch()
	var quitCh = make(chan bool)
	if GloballCnf.ShowToolbarIcon {
		quitCh = ShowStatusBar()
	}
	gin.SetMode(gin.ReleaseMode)
	route := gin.New()
	panicWriter := NewLazyFileWriter("panic.log")
	route.Use(gin.RecoveryWithWriter(panicWriter))
	route.NoRoute(notFoundHandler)
	route.POST("/copy", copyHandler)
	route.POST("/paste", pasteHandler)
	route.POST("/ping", pingHandler)
	route.POST("/download", downloadHandler)
	go func() {
		err := route.RunTLS(":"+GloballCnf.ServerPort, certFile, keyFile)
		if err != nil {
			logrus.Panic(err)
		}
	}()

	for {
		q := <-quitCh
		if q {
			break
		}
	}
}
