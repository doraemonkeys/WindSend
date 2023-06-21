package main

import (
	"bytes"
	"encoding/hex"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"regexp"
	"strings"

	"github.com/sirupsen/logrus"
)

const baseWebUrl = "https://ko0.com"

const submitUrl = "https://ko0.com/submit/"

const userAgent = "Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.71 Safari/537.36Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.11 (KHTML, like Gecko) Chrome/23.0.1271.64 Safari/537.11Mozilla/5.0 (Windows; U; Windows NT 6.1; en-US) AppleWebKit/534.16 (KHTML, like Gecko) Chrome/10.0.648.133 Safari/534.16"

var myUrl string

func InitMyUrl(secretKeyHex string) error {
	rKey := []byte(secretKeyHex)
	rkey, err := GetSha256(rKey)
	if err != nil {
		return err
	}
	rkey, err = GetSha256(rkey)
	if err != nil {
		return err
	}
	rkeyHex := hex.EncodeToString(rkey)
	myUrl = baseWebUrl + "/" + rkeyHex[0:16]
	logrus.Infof("myUrl: %s", myUrl)
	return nil
}

func GetContentFromWeb() ([]byte, error) {
	client, err := Get_client()
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequest("GET", myUrl, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", userAgent)
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	bodyText, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	re := regexp.MustCompile(`class[\s]*=[\s]*"txt_view">[\s]*<p>(.+)<\/p>`)
	match := re.FindStringSubmatch(string(bodyText))
	if len(match) == 0 {
		return nil, fmt.Errorf("can not find content")
	}
	// 读取
	encryptedata, err := hex.DecodeString(match[1])
	if err != nil {
		return nil, err
	}
	// 解密
	decryptedata, err := crypter.Decrypt(encryptedata)
	if err != nil {
		return nil, err
	}
	return decryptedata, nil
}

func PostContentToWeb(context []byte) error {
	encryptedata, err := crypter.Encrypt(context)
	if err != nil {
		return err
	}
	encryptedataHex := hex.EncodeToString(encryptedata)

	client, err := Get_client()
	if err != nil {
		return err
	}
	csrfmiddlewaretoken, err := getPostCsrfmiddlewaretoken(&client)
	if err != nil {
		return err
	}
	payload := &bytes.Buffer{}
	writer := multipart.NewWriter(payload)
	_ = writer.WriteField("csrfmiddlewaretoken", csrfmiddlewaretoken)
	_ = writer.WriteField("txt", encryptedataHex)
	_ = writer.WriteField("code", myUrl[strings.LastIndex(myUrl, "/")+1:])
	_ = writer.WriteField("sub_type", "T")
	_ = writer.WriteField("file", "")
	err = writer.Close()
	if err != nil {
		return err
	}
	req, err := http.NewRequest("POST", submitUrl, payload)
	if err != nil {
		return err
	}
	//fmt.Println(client.Jar.Cookies(req.URL))
	//fmt.Println(writer.FormDataContentType())
	req.Header.Set("Content-Type", writer.FormDataContentType())
	req.Header.Set("Referer", myUrl)
	req.Header.Set("User-Agent", userAgent)
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	bodyText, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}
	if !strings.Contains(string(bodyText), "success") {
		return fmt.Errorf("post content failed")
	}
	return nil
}

func getPostCsrfmiddlewaretoken(client *http.Client) (string, error) {
	req, err := http.NewRequest("GET", myUrl, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent", userAgent)
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	bodyText, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	return parseCsrfmiddlewaretoken(bodyText)
}

func parseCsrfmiddlewaretoken(content []byte) (string, error) {
	re := regexp.MustCompile(`name="csrfmiddlewaretoken" value="(.+)">`)
	match := re.FindStringSubmatch(string(content))
	if len(match) == 0 {
		return "", fmt.Errorf("can not find csrfmiddlewaretoken")
	}
	return match[1], nil
}
