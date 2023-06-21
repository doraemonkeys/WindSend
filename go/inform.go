package main

import (
	"github.com/go-toast/toast"
	"github.com/sirupsen/logrus"
)

// Inform 发出通知
func Inform(content string) {
	notification := toast.Notification{
		AppID:   "ClipboardSync",
		Title:   "Information",
		Message: content,
		//Icon:    "go.png", // This file must exist (remove this line if it doesn't)
	}
	err := notification.Push()
	if err != nil {
		logrus.Error(err)
	}
}
