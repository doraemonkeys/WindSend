cd flutter\clipboard

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