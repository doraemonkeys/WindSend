package main

import (
	"github.com/go-toast/toast"
	"github.com/sirupsen/logrus"
)

// Inform 发出通知
func Inform(content string, tittle string) {
	content = FilterNonPrintable(content)
	notification := toast.Notification{
		AppID:    ProgramName,
		Title:    tittle,
		Message:  content,
		Icon:     AppIconPath, // This file must exist (remove this line if it doesn't)
		Duration: toast.Short,
	}
	err := notification.Push()
	if err != nil {
		logrus.Error(err)
	}
}
