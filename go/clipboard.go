package main

import (
	"context"

	"golang.design/x/clipboard"
)

const (
	clipboardWatchDataTypeText  = "text"
	clipboardWatchDataTypeImage = "image"
	clipboardWatchDataEmpty     = "empty"
)

var clipboarDataType string

var clipboardWatchData []byte

// 监测剪切板变化
func clipboardWatch() {
	clipboarDataType = clipboardWatchDataEmpty
	// 剪切板一般不会更新太快，所以不用加锁
	go func() {
		ch := clipboard.Watch(context.TODO(), clipboard.FmtText)
		for data := range ch {
			clipboarDataType = clipboardWatchDataTypeText
			clipboardWatchData = data
			//fmt.Println("text:", string(data))
		}

	}()
	ch := clipboard.Watch(context.TODO(), clipboard.FmtImage)
	for data := range ch {
		clipboarDataType = clipboardWatchDataTypeImage
		clipboardWatchData = data
		//fmt.Println("image")
	}
}
