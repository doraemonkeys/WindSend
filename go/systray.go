package main

import (
	"runtime"
	"strconv"

	"fyne.io/systray"
	"github.com/doraemonkeys/WindSend/language"
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
var closeAllowSearchCH = make(chan struct{})
var allowSearch = false

//var liveCheckCH = make(chan struct{})

type setTitle interface {
	SetTitle(string)
}

func switchLang(items []Pair[setTitle, Pair[int, string]]) {
	for _, v := range items {
		v.First.SetTitle(language.Translate(v.Second.First) + v.Second.Second)
	}
}

func onReady(quitch chan bool) {
	systray.SetTemplateIcon(Data, Data)
	systray.SetTitle(ProgramName)
	systray.SetTooltip(ProgramName + " " + ProgramVersion)

	var filesNum int = 0

	// 添加菜单项
	mAddFils := systray.AddMenuItem(language.Translate(language.AddFiles)+" - 0",
		language.Translate(language.AddFiles))

	mClearFiles := systray.AddMenuItem(language.Translate(language.ClearFiles),
		language.Translate(language.ClearFiles))

	mCopyFromWeb := systray.AddMenuItem(language.Translate(language.Copy)+"[Web]",
		language.Translate(language.Copy)+"[Web]") // 添加菜单项

	// mPasteToWeb := systray.AddMenuItem("粘贴[Web]", "粘贴[Web]") // 添加菜单项
	mPasteToWeb := systray.AddMenuItem(language.Translate(language.Paste)+"[Web]",
		language.Translate(language.Paste)+"[Web]") // 添加菜单项

	systray.AddSeparator() //添加分割线
	// 文件保存路径
	mSavePath := systray.AddMenuItem(language.Translate(language.SavePath),
		language.Translate(language.SavePath))
	mHide := systray.AddMenuItem(language.Translate(language.HideIcon),
		language.Translate(language.HideIcon))
	// 仅一次
	mSubHide := mHide.AddSubMenuItem(language.Translate(language.OnlyOnce),
		language.Translate(language.OnlyOnce))
	// 永久隐藏
	mSubHideForever := mHide.AddSubMenuItem(language.Translate(language.HideForever),
		language.Translate(language.HideForever))
	mLang := systray.AddMenuItem("Language", "Language")
	mLangZH := mLang.AddSubMenuItemCheckbox("简体中文", "简体中文", language.GetLanguage() == language.ZH_CN_CODE)
	mLangEN := mLang.AddSubMenuItemCheckbox("English", "English", language.GetLanguage() == language.EN_US_CODE)
	// 自启动
	mAutoStart := systray.AddMenuItemCheckbox(language.Translate(language.AutoStart),
		language.Translate(language.AutoStart), GloballCnf.AutoStart)

	systray.AddSeparator() //添加分割线
	allowSearchM := systray.AddMenuItemCheckbox(language.Translate(language.QuickPair),
		language.Translate(language.QuickPairTip), allowSearch)
	mUrl := systray.AddMenuItem(language.Translate(language.OpenOfficialWebsite),
		language.Translate(language.OpenOfficialWebsite))
	mQuit := systray.AddMenuItem(language.Translate(language.Quit), "Quit the whole app")

	menuItems := []Pair[setTitle, Pair[int, string]]{
		{mAddFils, NewPair(language.AddFiles, " - 0")},
		{mClearFiles, NewPair(language.ClearFiles, "")},
		{mCopyFromWeb, NewPair(language.Copy, "[Web]")},
		{mPasteToWeb, NewPair(language.Paste, "[Web]")},
		{mSavePath, NewPair(language.SavePath, "")},
		{mHide, NewPair(language.HideIcon, "")},
		{mSubHide, NewPair(language.OnlyOnce, "")},
		{mSubHideForever, NewPair(language.HideForever, "")},
		{mAutoStart, NewPair(language.AutoStart, "")},
		{allowSearchM, NewPair(language.QuickPair, "")},
		{mUrl, NewPair(language.OpenOfficialWebsite, "")},
		{mQuit, NewPair(language.Quit, "")},
	}

	mClearFiles.Disable()
	for {
		select {
		case <-mLangZH.ClickedCh:
			language.SetLanguage(language.ZH_CN_CODE)
			switchLang(menuItems)
			mLangZH.Check()
			mLangEN.Uncheck()
			GloballCnf.Language = language.ZH_CN_CODE
			_ = GloballCnf.Save()
		case <-mLangEN.ClickedCh:
			language.SetLanguage(language.EN_US_CODE)
			switchLang(menuItems)
			mLangZH.Uncheck()
			mLangEN.Check()
			GloballCnf.Language = language.EN_US_CODE
			_ = GloballCnf.Save()
		case <-allowSearchM.ClickedCh:
			if allowSearchM.Checked() {
				allowSearchM.Uncheck()
				allowSearch = false
			} else {
				allowSearchM.Check()
				allowSearch = true
			}
		case <-closeAllowSearchCH:
			allowSearchM.Uncheck()
			allowSearch = false
		case <-mAddFils.ClickedCh:
			n, err := SelectFiles()
			if err != nil {
				logrus.Error("failed to select files:", err)
				continue
			}
			if n == 0 {
				// user canceled
				continue
			}
			if filesNum == 0 && n > 0 {
				mClearFiles.Enable()
			}
			filesNum += n
			mAddFils.SetTitle(language.Translate(language.AddFiles) + " - " + strconv.Itoa(filesNum))
		case <-mClearFiles.ClickedCh:
			SelectedFiles = nil
			filesNum = 0
			mAddFils.SetTitle(language.Translate(language.AddFiles) + " - " + strconv.Itoa(filesNum))
			mClearFiles.Disable()
		case <-clearFilesCH:
			SelectedFiles = nil
			filesNum = 0
			mAddFils.SetTitle(language.Translate(language.AddFiles) + " - " + strconv.Itoa(filesNum))
			mClearFiles.Disable()
		case <-mUrl.ClickedCh:
			err := OpenUrl(ProgramUrl)
			if err != nil {
				logrus.Error("failed to open url:", err)
				Inform(err.Error(), ProgramName)
			}
			//logrus.Info("打开官网")
		case <-mSubHide.ClickedCh:
			systray.Quit()
			quitch <- false
			return
		case <-mSubHideForever.ClickedCh:
			GloballCnf.ShowSystrayIcon = false
			_ = GloballCnf.SaveAndSet()
			systray.Quit()
			quitch <- false
			return
		case <-mAutoStart.ClickedCh:
			GloballCnf.AutoStart = !GloballCnf.AutoStart
			err := GloballCnf.SaveAndSet()
			if err != nil {
				logrus.Error("failed to save config:", err)
				Inform(language.Translate(language.SaveConfigFailed)+":"+err.Error(), ProgramName)
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
				logrus.Error("failed to select folder:", err)
				continue
			}
			GloballCnf.SavePath = path
			err = GloballCnf.Save()
			if err != nil {
				logrus.Error("failed to save config:", err)
				Inform(language.Translate(language.SaveConfigFailed)+":"+err.Error(), ProgramName)
			}

		case <-mPasteToWeb.ClickedCh:
			clipboarDataType, clipboardWatchData := clipboardData.Get()
			if clipboarDataType != clipboardWatchDataTypeText {
				Inform(language.Translate(language.ClipboardNotText), ProgramName)
			} else if clipboarDataType == clipboardWatchDataTypeText {
				err := PostContentToWeb(clipboardWatchData)
				if err != nil {
					logrus.Error("failed to paste to web:", err)
					Inform(language.Translate(language.PasteToWebFailed)+":"+err.Error(), ProgramName)
				}
				Inform(language.Translate(language.PasteToWebSuccess), ProgramName)
			}
		case <-mCopyFromWeb.ClickedCh:
			text, err := GetContentFromWeb()
			if err != nil {
				logrus.Error("failed to copy from web:", err)
				Inform(language.Translate(language.CopyFromWebFailed)+":"+err.Error(), ProgramName)
			} else {
				clipboard.Write(clipboard.FmtText, text)
				textRune := []rune(string(text))
				showLen := 80
				if len(textRune) >= showLen {
					Inform(string(textRune[:showLen])+"...", ProgramName)
				} else {
					Inform(string(textRune), ProgramName)
				}
			}
		case <-mQuit.ClickedCh:
			systray.Quit()
			quitch <- true
			return
		}
	}
}
