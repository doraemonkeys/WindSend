package main

import (
	"crypto/tls"
	"fmt"
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

// go build -ldflags "-H=windowsgui"
// func main() {
// 	runtime.UnlockOSThread()
// 	go clipboardWatch()
// 	var quitCh = make(chan bool)
// 	if GloballCnf.ShowToolbarIcon {
// 		quitCh = ShowStatusBar()
// 	}
// 	gin.SetMode(gin.ReleaseMode)
// 	route := gin.New()
// 	panicWriter := NewLazyFileWriter("panic.log")
// 	route.Use(gin.RecoveryWithWriter(panicWriter))
// 	route.NoRoute(notFoundHandler)
// 	route.POST("/copy", copyHandler)
// 	route.POST("/paste", pasteHandler)
// 	route.POST("/ping", pingHandler)
// 	route.GET("/download", downloadHandler)
// 	go func() {
// 		err := route.RunTLS(":"+GloballCnf.ServerPort, certFile, keyFile)
// 		if err != nil {
// 			logrus.Panic(err)
// 		}
// 	}()

// 	for {
// 		q := <-quitCh
// 		if q {
// 			break
// 		}
// 	}
// }

func main() {
	runtime.UnlockOSThread()
	go clipboardWatch()
	var quitCh = make(chan bool)
	if GloballCnf.ShowToolbarIcon {
		quitCh = ShowStatusBar()
	}
	cert, err := tls.LoadX509KeyPair("./tls/cert.pem", "./tls/key.pem")
	if err != nil {
		panic(err)
	}
	config := &tls.Config{
		Certificates: []tls.Certificate{cert},
		// 是否跳过证书验证
		InsecureSkipVerify: true,
	}
	listen, err := tls.Listen("tcp", ":6779", config)
	if err != nil {
		fmt.Println("listen failed, err:", err)
		return
	}
	defer listen.Close()
	go func() {
		for {
			conn, err := listen.Accept()
			if err != nil {
				fmt.Println("accept failed, err:", err)
				continue
			}
			go process(conn)
		}
	}()
	for {
		q := <-quitCh
		if q {
			break
		}
	}
}
