@echo off

cd go
echo %cd%

go build -ldflags "-H=windowsgui"

move clipboard-go.exe ../bin/clipboard-go-amd64-windows/clipboard-go.exe

cd ../flutter/clipboard
echo %cd%

call flutter build apk --split-per-abi 

if %errorlevel% equ 0 (
  echo Success!
  move build\app\outputs\flutter-apk\app-arm64-v8a-release.apk ..\..\bin\clipboard-flutter-arm64-v8a-release.apk
  move build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk ..\..\bin\clipboard-flutter-armeabi-v7a-release.apk
  move build\app\outputs\flutter-apk\app-x86_64-release.apk ..\..\bin\clipboard-flutter-x86_64-release.apk
) else (
  echo Failed!
)

pause
