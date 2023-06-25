package main

var SelectedFiles []string

// const MaxAllowedSize = 1024 * 1024 * 5000

func SelectFiles() (int, error) {
	ret, err := SelectMultiFilesOnWindows()
	if err != nil {
		return 0, err
	}
	if len(ret) != 0 {
		SelectedFiles = append(SelectedFiles, ret...)
		//fmt.Println("SelectedFiles:", SelectedFiles)
	}
	return len(ret), nil
}
