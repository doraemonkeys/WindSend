package main

import (
	"github.com/go-toast/toast"
	"github.com/sirupsen/logrus"
)

// Inform 发出通知
func Inform(content string) {
	notification := toast.Notification{
		AppID:   ProgramName,
		Title:   "Information",
		Message: content,
		//Icon:    "go.png", // This file must exist (remove this line if it doesn't)
		Duration: toast.Short, //5s
	}
	err := notification.Push()
	if err != nil {
		logrus.Error(err)
	}
}

// type UploadDelayedNotification struct {
// 	interval time.Duration
// 	fileNums int
// 	lastTime time.Time
// 	waiting  bool
// 	// 用于保护waiting与fileNums
// 	lock *sync.Mutex
// }

// func NewUploadDelayedNotification(interval time.Duration) *UploadDelayedNotification {
// 	return &UploadDelayedNotification{
// 		interval: interval,
// 		lock:     new(sync.Mutex),
// 	}
// }

// func (n *UploadDelayedNotification) notify() {
// 	n.lastTime = time.Now()
// 	msg := fmt.Sprintf("%d个文件已保存到 %s", n.fileNums, GloballCnf.SavePath)
// 	n.fileNums = 0
// 	Inform(msg)
// 	if n.fileNums != 0 {
// 		logrus.Error("something wrong with UploadDelayedNotification, fileNums should be 0")
// 	}
// }

// func (n *UploadDelayedNotification) TryNotify() {
// 	n.lock.Lock()
// 	defer n.lock.Unlock()
// 	n.fileNums++
// 	if n.waiting {
// 		return
// 	}
// 	if time.Since(n.lastTime) > n.interval {
// 		n.notify()
// 		return
// 	}
// 	go n.delayedNotify(n.interval - time.Since(n.lastTime))
// }

// func (n *UploadDelayedNotification) delayedNotify(d time.Duration) {
// 	n.lock.Lock()
// 	n.waiting = true
// 	n.lock.Unlock()

// 	time.Sleep(d)

// 	n.lock.Lock()
// 	n.notify()
// 	n.waiting = false
// 	n.lock.Unlock()
// }

// var UploadNotifier *UploadDelayedNotification = NewUploadDelayedNotification(5 * time.Second)
