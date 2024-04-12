package main

import (
	"context"
	"errors"
	"sync"

	"golang.design/x/clipboard"

	"github.com/lxn/win"
	"golang.org/x/sys/windows"
)

const (
	clipboardWatchDataTypeText  = "text"
	clipboardWatchDataTypeImage = "image"
	clipboardWatchDataEmpty     = "empty"
)

var clipboardData = clipboardDataStruct{
	dataType: clipboardWatchDataEmpty,
	data:     nil,
	lock:     new(sync.RWMutex)}

type clipboardDataStruct struct {
	dataType string
	data     []byte
	lock     *sync.RWMutex
}

func (c *clipboardDataStruct) Set(dataType string, data []byte) {
	c.lock.Lock()
	defer c.lock.Unlock()
	c.dataType = dataType
	c.data = data
}

func (c *clipboardDataStruct) Get() (dataType string, data []byte) {
	c.lock.RLock()
	defer c.lock.RUnlock()
	return c.dataType, c.data
}

func clipboardWatcher() {
	go func() {
		ch := clipboard.Watch(context.TODO(), clipboard.FmtText)
		for data := range ch {
			clipboardData.Set(clipboardWatchDataTypeText, data)
			// fmt.Println("text:", string(data))
		}
	}()
	ch := clipboard.Watch(context.TODO(), clipboard.FmtImage)
	for data := range ch {
		clipboardData.Set(clipboardWatchDataTypeImage, data)
		//fmt.Println("image")
	}
}

func (c *ClipboardService) withOpenClipboard(f func() error) error {
	if !win.OpenClipboard(c.hwnd) {
		return errors.New("OpenClipboard failed")
	}
	defer win.CloseClipboard()

	return f()
}

// https://github.com/YanxinTang/clipboard-online/blob/master/utils/clipboard.go
func (c *ClipboardService) Files() (filenames []string, err error) {
	err = c.withOpenClipboard(func() error {
		hMem := win.HGLOBAL(win.GetClipboardData(win.CF_HDROP))
		if hMem == 0 {
			return errors.New("GetClipboardData failed")
		}
		p := win.GlobalLock(hMem)
		if p == nil {
			return errors.New("GlobalLock failed")
		}
		defer win.GlobalUnlock(hMem)
		filesCount := win.DragQueryFile(win.HDROP(p), 0xFFFFFFFF, nil, 0)
		filenames = make([]string, 0, filesCount)
		buf := make([]uint16, win.MAX_PATH)
		for i := uint(0); i < filesCount; i++ {
			win.DragQueryFile(win.HDROP(p), i, &buf[0], win.MAX_PATH)
			filenames = append(filenames, windows.UTF16ToString(buf))
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return
}

var clipboardS ClipboardService

// Clipboard returns an object that provides access to the system clipboard.
func Clipboard() *ClipboardService {
	return &clipboardS
}

// ClipboardService provides access to the system clipboard.
type ClipboardService struct {
	hwnd win.HWND
	// contentsChangedPublisher walk.EventPublisher
}

// Clear clears the contents of the clipboard.
func (c *ClipboardService) Clear() error {
	return c.withOpenClipboard(func() error {
		if !win.EmptyClipboard() {
			return errors.New("EmptyClipboard failed")
		}

		return nil
	})
}
