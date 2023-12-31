package main

import (
	"runtime"
	"strconv"

	"fyne.io/systray"
	"github.com/sirupsen/logrus"
	"golang.design/x/clipboard"
)

// quitCh 返回true表示退出程序
// quitCh 返回false表示隐藏状态栏图标
func ShowStatusBar() (quitCh chan bool) {
	quitCh = make(chan bool)
	onReady := func() {
		onReady(quitCh)
	}
	// onExit 在退出调用systray.Quit()方法时执行
	go func() {
		runtime.LockOSThread()
		systray.Run(onReady, nil)
	}()
	return quitCh
}

var clearFilesCH = make(chan struct{})

//var liveCheckCH = make(chan struct{})

func onReady(quitch chan bool) {

	systray.SetTemplateIcon(Data, Data)
	systray.SetTitle("剪切板同步")
	systray.SetTooltip(ProgramName + " " + ProgramVersion)

	var filesNum int = 0
	mAddFils := systray.AddMenuItem("添加文件 - 0", "添加文件") // 添加菜单项

	//mChecked := systray.AddMenuItemCheckbox("Unchecked", "Check Me", true) // 添加菜单项状态选择
	mClearFiles := systray.AddMenuItem("清空文件", "清空文件")

	mCopyFromWeb := systray.AddMenuItem("复制[Web]", "复制[Web]") // 添加菜单项
	mPasteToWeb := systray.AddMenuItem("粘贴[Web]", "粘贴[Web]")  // 添加菜单项

	systray.AddSeparator() //添加分割线
	mHide := systray.AddMenuItem("隐藏图标", "隐藏图标")
	// 仅一次
	mSubHide := mHide.AddSubMenuItem("仅一次", "仅一次")
	// 永久隐藏
	mSubHideForever := mHide.AddSubMenuItem("永久隐藏", "永久隐藏")

	// 自启动
	mAutoStart := systray.AddMenuItemCheckbox("自启动", "自启动", GloballCnf.AutoStart)

	// 文件保存路径
	mSavePath := systray.AddMenuItem("文件保存路径", "文件保存路径")

	mUrl := systray.AddMenuItem("打开官网", ProgramUrl)
	mQuit := systray.AddMenuItem("退出", "Quit the whole app")

	mClearFiles.Disable()
	for {
		select {
		case <-mAddFils.ClickedCh:
			n, err := SelectFiles()
			if err != nil {
				logrus.Error("选择文件失败：", err)
				continue
			}
			if err == nil && n == 0 {
				// user canceled
				continue
			}
			if filesNum == 0 && n > 0 {
				mClearFiles.Enable()
			}
			filesNum += n
			mAddFils.SetTitle("添加文件 - " + strconv.Itoa(filesNum))
		case <-mClearFiles.ClickedCh:
			SelectedFiles = nil
			filesNum = 0
			mAddFils.SetTitle("添加文件 - " + strconv.Itoa(filesNum))
			mClearFiles.Disable()
		case <-clearFilesCH:
			SelectedFiles = nil
			filesNum = 0
			mAddFils.SetTitle("添加文件 - " + strconv.Itoa(filesNum))
			mClearFiles.Disable()
		case <-mUrl.ClickedCh:
			OpenUrl(ProgramUrl)
			//logrus.Info("打开官网")
		case <-mSubHide.ClickedCh:
			systray.Quit()
			quitch <- false
			return
		case <-mSubHideForever.ClickedCh:
			GloballCnf.ShowToolbarIcon = false
			GloballCnf.SaveAndSet()
			systray.Quit()
			quitch <- false
			return
		case <-mAutoStart.ClickedCh:
			GloballCnf.AutoStart = !GloballCnf.AutoStart
			err := GloballCnf.SaveAndSet()
			if err != nil {
				logrus.Error("保存配置失败：", err)
				Inform("保存配置失败：" + err.Error())
			} else {
				if mAutoStart.Checked() {
					mAutoStart.Uncheck()
				} else {
					mAutoStart.Check()
				}
			}
		case <-mSavePath.ClickedCh:
			path, err := SelectFolderOnWindows(ProgramName)
			if err != nil {
				logrus.Error("选择文件夹失败：", err)
				continue
			}
			GloballCnf.SavePath = path
			err = GloballCnf.Save()
			if err != nil {
				logrus.Error("保存配置失败：", err)
				Inform("保存配置失败：" + err.Error())
			}

		case <-mPasteToWeb.ClickedCh:
			if clipboarDataType != clipboardWatchDataTypeText {
				Inform("当前剪切板数据不是文本")
			} else if clipboarDataType == clipboardWatchDataTypeText {
				err := PostContentToWeb(clipboardWatchData)
				if err != nil {
					logrus.Error("粘贴到Web失败：", err)
					Inform("粘贴到Web失败：" + err.Error())
				}
				Inform("粘贴到Web成功")
			}
		case <-mCopyFromWeb.ClickedCh:
			text, err := GetContentFromWeb()
			if err != nil {
				logrus.Error("从Web复制失败：", err)
				Inform("从Web复制失败：" + err.Error())
			} else {
				clipboard.Write(clipboard.FmtText, text)
				textRune := []rune(string(text))
				showLen := 80
				if len(textRune) >= showLen {
					Inform(string(textRune[:showLen]) + "...")
				} else {
					Inform(string(textRune))
				}
			}
		case <-mQuit.ClickedCh:
			systray.Quit()
			quitch <- true
			return
		}
	}

}
