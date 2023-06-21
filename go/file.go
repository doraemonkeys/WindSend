package main

import "fmt"

var SelectedFiles []string
var SelectedFilesSize int64 = 0

func SelectFiles() (int, error) {
	ret, err := SelectMultiFilesOnWindows()
	if err != nil {
		return 0, err
	}

	// 检查文件大小
	var totalSize int64 = 0
	for _, v := range ret {
		temp, err := GetFileSize(v)
		if err != nil {
			return 0, err
		}
		totalSize += temp
	}
	if SelectedFilesSize+totalSize > MaxAllowedSize {
		return 0, fmt.Errorf("选择的文件总大小超过了限制(%v)MB", MaxAllowedSize/1024/1024)
	}
	SelectedFilesSize += totalSize
	if len(ret) != 0 {
		SelectedFiles = append(SelectedFiles, ret...)
		//fmt.Println("SelectedFiles:", SelectedFiles)
	}
	return len(ret), nil
}
