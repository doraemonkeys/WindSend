package language

const (
	AddFiles = iota
	ClearFiles
	Copy
	Paste
	SavePath
	HideIcon
	OnlyOnce
	HideForever
	AutoStart
	QuickPair
	QuickPairTip
	OpenOfficialWebsite
	Quit
	SelectFileFailed
	SelectDirFailed
	SaveConfigFailed
	ClipboardNotText
	PasteToWebSuccess
	PasteToWebFailed
	CopyFromWebFailed
	ClipboardIsEmpty
	DirCreated
	NFilesSavedTo
)

var _ZH_CN = map[int]string{
	AddFiles:            "添加文件",
	ClearFiles:          "清空文件",
	Copy:                "复制",
	Paste:               "粘贴",
	SavePath:            "文件保存路径",
	HideIcon:            "隐藏图标",
	OnlyOnce:            "仅一次",
	HideForever:         "永久隐藏",
	AutoStart:           "开机自启",
	QuickPair:           "快速配对",
	QuickPairTip:        "快速配对将在第一次成功后自动关闭",
	OpenOfficialWebsite: "打开官网",
	Quit:                "退出",
	SelectFileFailed:    "选择文件失败",
	SelectDirFailed:     "选择文件夹失败",
	SaveConfigFailed:    "保存配置失败",
	ClipboardNotText:    "当前剪切板内容不是文本",
	PasteToWebSuccess:   "粘贴到web成功",
	PasteToWebFailed:    "粘贴到web失败",
	CopyFromWebFailed:   "从web复制文本失败",
	ClipboardIsEmpty:    "你还没有复制任何内容",
	DirCreated:          "文件夹创建成功",
	NFilesSavedTo:       "个文件保存到",
}

var _EN_US = map[int]string{
	AddFiles:            "Add Files",
	ClearFiles:          "Clear Files",
	Copy:                "Copy",
	Paste:               "Paste",
	SavePath:            "Save Path",
	HideIcon:            "Hide Icon",
	OnlyOnce:            "Only Once",
	HideForever:         "Hide Forever",
	AutoStart:           "Auto Start",
	QuickPair:           "Quick Pair",
	QuickPairTip:        "Quick Pair will be closed automatically after successful pairing",
	OpenOfficialWebsite: "Open Website",
	Quit:                "Quit",
	SelectFileFailed:    "Select File Failed",
	SelectDirFailed:     "Select Dir Failed",
	SaveConfigFailed:    "Save Config Failed",
	ClipboardNotText:    "Clipboard content is not text",
	PasteToWebSuccess:   "Successfully pasted to web",
	PasteToWebFailed:    "Failed to paste to web",
	CopyFromWebFailed:   "Failed to copy text from web",
	ClipboardIsEmpty:    "You haven't copied anything yet",
	DirCreated:          "Directory created successfully",
	NFilesSavedTo:       "files saved to",
}

var SupportedLanguageCode = []string{EN_US_CODE, ZH_CN_CODE}

var curLang = EN_US_CODE

const ZH_CN_CODE = "zh"
const EN_US_CODE = "en"

func SetLanguage(l string) {
	for _, v := range SupportedLanguageCode {
		if v == l {
			curLang = l
			break
		}
	}
}

func GetLanguage() string {
	return curLang
}

func Translate(key int) string {
	switch curLang {
	case ZH_CN_CODE:
		return _ZH_CN[key]
	case EN_US_CODE:
		return _EN_US[key]
	default:
		return _EN_US[key]
	}
}
