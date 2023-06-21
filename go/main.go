package main

import (
	"github.com/Doraemonkeys/mylog"
	"github.com/gin-gonic/gin"
)

var crypter *CbcAESCrypt

const ProgramName = "clipboard-go"
const ProgramUrl = "https://github.com/Doraemonkeys/clipboard-go"

func init() {
	cnf := initGlobalConfig()
	var err error
	crypter, err = NewAESCryptFromHex(cnf.SecretKeyHex)
	if err != nil {
		panic(err)
	}
	var lofCnf = mylog.LogConfig{}
	lofCnf.MaxLogSize = 1024 * 1024 * 10
	lofCnf.MaxKeepDays = 100
	err = mylog.InitGlobalLogger(lofCnf)
	if err != nil {
		panic(err)
	}
	err = InitMyUrl(cnf.SecretKeyHex)
	if err != nil {
		panic(err)
	}
}

// go build -ldflags "-H=windowsgui"
func main() {
	go clipboardWatch()
	var quitCh = make(chan bool)
	if GloballCnf.ShowToolbarIcon {
		quitCh = ShowStatusBar()
	}
	gin.SetMode(gin.ReleaseMode)
	route := gin.New()
	panicWriter := NewLazyFileWriter("panic.log")
	route.Use(gin.RecoveryWithWriter(panicWriter))
	route.POST("/copy", copyHandler)
	route.POST("/paste", pasteHandler)
	route.POST("/ping", pingHandler)
	go route.Run(":" + GloballCnf.ServerPort)

	for {
		q := <-quitCh
		if q {
			break
		}
	}
}
