@echo off


set ServerProgramName=WindSend-S
set goServerProgramName=%ServerProgramName%-Go
set rustServerProgramName=%ServerProgramName%-Rust



@REM build go server
cd go
echo %cd%
go build -ldflags "-H=windowsgui" -o %goServerProgramName%.exe

cd ../bin
md %goServerProgramName%-amd64-windows
move ../go/%goServerProgramName%.exe %goServerProgramName%-amd64-windows/%goServerProgramName%.exe
xcopy ..\README.md %goServerProgramName%-amd64-windows /y
zip -r %goServerProgramName%-amd64-windows.zip %goServerProgramName%-amd64-windows



@REM 输入version
set /p version=version:v
set versionStr=version: %version%
echo %versionStr%


@REM build rust server
set rustPjName=wind_send
cd ../windSend-rs
echo %cd%

@REM 修改 Cargo.toml 中的版本号 (version = "x.x.x")，不能误伤其他地方的version
call sed -i '0,/version = "[0-9]\+\.[0-9]\+\.[0-9]\+"/s/version = "[0-9]\+\.[0-9]\+\.[0-9]\+"/version = "%version%"/' Cargo.toml
@REM 修改 src/main.rs 中的版本号 (static PROGRAM_VERSION: &str = "x.x.x";)
call sed -i "s/static PROGRAM_VERSION:.*/static PROGRAM_VERSION: \&str = \"%version%\";/" src/main.rs

cargo build --release
cd ../bin
md %rustServerProgramName%-amd64-windows
move ..\windSend-rs\target\release\%rustPjName%.exe %rustServerProgramName%-amd64-windows/%rustServerProgramName%.exe
xcopy ..\README.md %rustServerProgramName%-amd64-windows /y
zip -r %rustServerProgramName%-amd64-windows.zip %rustServerProgramName%-amd64-windows




pause



@REM build flutter client
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

@REM 修改 pubspec.yaml 中的版本号 version:
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
  xcopy ..\..\README.md ..\..\bin\%appName%-flutter-amd64-windows\ /y
  cd ..\..\bin
  zip -r %appName%-flutter-client-amd64-windows.zip %appName%-flutter-amd64-windows
) else (
  echo Build Windows Failed!
)

pause
