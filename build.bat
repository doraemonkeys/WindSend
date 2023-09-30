@echo off

cd go
echo %cd%

set ServerProgramName=WindSend-S

go build -ldflags "-H=windowsgui" -o %ServerProgramName%.exe

cd ../bin
md %ServerProgramName%-amd64-windows
move ../go/%ServerProgramName%.exe %ServerProgramName%-amd64-windows/%ServerProgramName%.exe
zip -r %ServerProgramName%-amd64-windows.zip %ServerProgramName%-amd64-windows



cd ../flutter/clipboard
echo %cd%

call flutter clean

if %errorlevel% equ 0 (
  echo Clean Success!
) else (
  echo Clean Failed!
  pause
)

set appName=WindSend

@REM 输入version
set /p version=version:v

@REM 修改 pubspec.yaml 中的版本号 version:
set versionStr=version: %version%
echo %versionStr%
call sed -i "s/version: .*/%versionStr%/" pubspec.yaml

call flutter build apk --split-per-abi 

if %errorlevel% equ 0 (
  echo Build APK Success!
  move build\app\outputs\flutter-apk\app-arm64-v8a-release.apk ..\..\bin\%appName%-flutter-arm64-v8a-release.apk
  move build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk ..\..\bin\%appName%-flutter-armeabi-v7a-release.apk
  move build\app\outputs\flutter-apk\app-x86_64-release.apk ..\..\bin\%appName%-flutter-x86_64-release.apk
) else (
  echo Build APK Failed!
  pause
)

call flutter build windows --release

if %errorlevel% equ 0 (
  echo Build Windows Success!
  xcopy /s /y build\windows\runner\Release ..\..\bin\%appName%-flutter-amd64-windows\
  cd ..\..\bin
  zip -r %appName%-flutter-client-amd64-windows.zip %appName%-flutter-amd64-windows
) else (
  echo Build Windows Failed!
)

pause
