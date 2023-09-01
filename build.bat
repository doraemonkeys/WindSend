@echo off

cd go
echo %cd%

go build -ldflags "-H=windowsgui"

cd ../bin
md clipboard-go-amd64-windows
move ../go/clipboard-go.exe clipboard-go-amd64-windows/clipboard-go.exe
zip -r clipboard-go-amd64-windows.zip clipboard-go-amd64-windows

cd ../flutter/clipboard
echo %cd%

call flutter clean

if %errorlevel% equ 0 (
  echo Clean Success!
) else (
  echo Clean Failed!
  pause
)

@REM 输入version
set /p version=version:v

@REM 修改 pubspec.yaml 中的版本号 version:
set versionStr=version: %version%
echo %versionStr%
call sed -i "s/version: .*/%versionStr%/" pubspec.yaml

call flutter build apk --split-per-abi 

if %errorlevel% equ 0 (
  echo Build APK Success!
  move build\app\outputs\flutter-apk\app-arm64-v8a-release.apk ..\..\bin\clipboard-flutter-arm64-v8a-release.apk
  move build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk ..\..\bin\clipboard-flutter-armeabi-v7a-release.apk
  move build\app\outputs\flutter-apk\app-x86_64-release.apk ..\..\bin\clipboard-flutter-x86_64-release.apk
) else (
  echo Build APK Failed!
  pause
)

call flutter build windows --release

if %errorlevel% equ 0 (
  echo Build Windows Success!
  xcopy /s /y build\windows\runner\Release ..\..\bin\clipboard-flutter-amd64-windows\
  cd ..\..\bin
  zip -r clipboard-flutter-client-amd64-windows.zip clipboard-flutter-amd64-windows
  @REM move build\windows\runner\Release ..\..\bin\clipboard-flutter-amd64-windows
  @REM cd ..\..\bin
  @REM zip -r clipboard-flutter-amd64-windows.zip clipboard-flutter-amd64-windows
) else (
  echo Build Windows Failed!
)

pause
