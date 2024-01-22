set appName=WindSend

cd flutter\wind_send

call flutter clean

if %errorlevel% equ 0 (
  echo Clean Success!
) else (
  echo Clean Failed!
  pause
)

call flutter build windows --release

if %errorlevel% equ 0 (
  echo Build Windows Success!
  xcopy /s /y build\windows\x64\runner\Release ..\..\bin\%appName%-flutter-amd64-windows\
  xcopy ..\..\README.md ..\..\bin\%appName%-flutter-amd64-windows\ /y
  cd ..\..\bin
  zip -r %appName%-flutter-client-amd64-windows.zip %appName%-flutter-amd64-windows
  @REM move build\windows\runner\Release ..\..\bin\clipboard-flutter-amd64-windows
  @REM cd ..\..\bin
  @REM zip -r clipboard-flutter-amd64-windows.zip clipboard-flutter-amd64-windows
) else (
  echo Build Windows Failed!
)

pause