@echo off


set ServerProgramName=WindSend-S
set goServerProgramName=%ServerProgramName%-Go
set rustServerProgramName=%ServerProgramName%-Rust
set "ServerProgramIconName=icon-192.png"
set CURRENT_DIR=%cd%


@REM 输入version
set /p version=version:v
set versionStr=version: %version%
echo %versionStr%



@REM @REM build go server[amd64]
@REM cd go
@REM echo %cd%
@REM @REM 修改 main.go 中的版本号 (const ProgramVersion = "x.x.x")
@REM call sed -i "s/const ProgramVersion = .*/const ProgramVersion = \"%version%\"/" main.go

@REM go build -ldflags "-H=windowsgui" -o %goServerProgramName%.exe

@REM cd ../bin
@REM md %goServerProgramName%-x86_64-windows
@REM move ../go/%goServerProgramName%.exe %goServerProgramName%-x86_64-windows/%goServerProgramName%.exe
@REM xcopy ..\README.md %goServerProgramName%-x86_64-windows /y
@REM xcopy ..\README-EN.md %goServerProgramName%-x86_64-windows /y
@REM xcopy "..\go\%ServerProgramIconName%" %goServerProgramName%-x86_64-windows /y
@REM zip -r %goServerProgramName%-x86_64-windows.zip %goServerProgramName%-x86_64-windows
@REM cd ../go  


@REM @REM build go server[arm64]
@REM set GOARCH=arm64
@REM echo %cd%
@REM @REM 修改 main.go 中的版本号 (const ProgramVersion = "x.x.x")
@REM call sed -i "s/const ProgramVersion = .*/const ProgramVersion = \"%version%\"/" main.go

@REM go build -ldflags "-H=windowsgui" -o %goServerProgramName%.exe

@REM cd ../bin
@REM md %goServerProgramName%-arm64-windows
@REM move ../go/%goServerProgramName%.exe %goServerProgramName%-arm64-windows/%goServerProgramName%.exe
@REM xcopy ..\README.md %goServerProgramName%-arm64-windows /y
@REM xcopy ..\README-EN.md %goServerProgramName%-arm64-windows /y
@REM xcopy "..\go\%ServerProgramIconName%" %goServerProgramName%-arm64-windows /y
@REM zip -r %goServerProgramName%-arm64-windows.zip %goServerProgramName%-arm64-windows
@REM cd ../go




@REM build rust server
set rustPjName=wind_send
cd %CURRENT_DIR%
cd ./windSend-rs
echo %cd%

@REM 修改 Cargo.toml 中的版本号 (version = "x.x.x")
call sed -i '0,/version = "[0-9]\+\.[0-9]\+\.[0-9]\+"/s/version = "[0-9]\+\.[0-9]\+\.[0-9]\+"/version = "%version%"/' Cargo.toml
@REM 修改 src/main.rs 中的版本号 (static PROGRAM_VERSION: &str = "x.x.x";)
@REM call sed -i "s/static PROGRAM_VERSION:.*/static PROGRAM_VERSION: \&str = \"%version%\";/" src/main.rs

cargo build --release
cd ../bin
md %rustServerProgramName%-x86_64-windows
move ..\windSend-rs\target\release\%rustPjName%.exe %rustServerProgramName%-x86_64-windows/%rustServerProgramName%.exe
xcopy ..\README.md %rustServerProgramName%-x86_64-windows /y
xcopy ..\README-EN.md %rustServerProgramName%-x86_64-windows /y
xcopy "..\windSend-rs\%ServerProgramIconName%" %rustServerProgramName%-x86_64-windows /y
zip -r %rustServerProgramName%-x86_64-windows.zip %rustServerProgramName%-x86_64-windows




pause



@REM build flutter client
cd ../flutter/wind_send
echo %cd%

@REM call flutter clean
@REM if %errorlevel% equ 0 (
@REM   echo Clean Success!
@REM ) else (
@REM   echo Clean Failed!
@REM   pause
@REM )

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
)


pause
call flutter build windows --release

if %errorlevel% equ 0 (
  echo Build Windows Success!
  xcopy /s /y build\windows\x64\runner\Release ..\..\bin\%appName%-flutter-x86_64-windows\
  xcopy ..\..\README.md ..\..\bin\%appName%-flutter-x86_64-windows\ /y
  cd ..\..\bin
  zip -r %appName%-flutter-client-x86_64-windows.zip %appName%-flutter-x86_64-windows
) else (
  echo Build Windows Failed!
)

