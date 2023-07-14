package main

import (
	"bufio"
	"io"
	"net"
	"os"

	"github.com/sirupsen/logrus"
)

func downloadHandler(conn net.Conn, head headInfo) {

	var respHead RespHead
	respHead.Code = 200
	respHead.Msg = "start download"
	respHead.DataType = DataTypeBinary
	respHead.DataLen = head.End - head.Start
	err := sendHead(conn, respHead)
	if err != nil {
		logrus.Error("send head failed, err:", err)
		return
	}

	logrus.Debugln("downloading file ", head.Path, " from ", head.Start, " to ", head.End)
	file, err := os.Open(head.Path)
	if err != nil {
		logrus.Error("open file failed, err:", err)
		return
	}
	defer file.Close()

	expectedSize := head.End - head.Start
	const maxBufSize = 1024 * 1024 * 30
	var bufSize = min(expectedSize, maxBufSize)

	var filereader = NewFilePartReader(file, int(head.Start), int(head.End))

	var reader = bufio.NewReaderSize(filereader, int(bufSize))
	n, err := reader.WriteTo(conn)
	if err != nil {
		logrus.Error("write to conn failed, err:", err)
		return
	}
	if n != expectedSize {
		logrus.Warnln("write to conn failed, n != expectedSize, n:", n, ", expectedSize:", expectedSize)
	}
}

type FilePartReader struct {
	file    *os.File
	start   int
	end     int
	written int
}

// [start, end)
func NewFilePartReader(file *os.File, start, end int) *FilePartReader {
	return &FilePartReader{
		file:  file,
		start: start,
		end:   end,
	}
}
func (fr *FilePartReader) Read(p []byte) (n int, err error) {
	if fr.written >= fr.end-fr.start {
		return 0, io.EOF
	}
	n, err = fr.file.ReadAt(p, int64(fr.start+fr.written))
	if fr.written+n > fr.end-fr.start {
		n = fr.end - fr.start - fr.written
		fr.written = fr.end - fr.start
	} else {
		fr.written += n
	}
	return
}
