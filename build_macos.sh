#!/bin/bash

#shellcheck source=/dev/null
source ./env.sh
WINDSEND_RUST_SERVER_BIN_NAME="WindSend-S-Rust"
mkdir -p ./bin
chmod +x ./*.sh

# 检查环境变量是否已经设置
if [ -z "$WINDSEND_PROJECT_VERSION" ]; then
    read -rp "WINDSEND_PROJECT_VERSION:v" WINDSEND_PROJECT_VERSION
fi

# 若指定了版本号，则修改项目中的版本号
if [ -n "$WINDSEND_PROJECT_VERSION" ]; then
    echo "WINDSEND_PROJECT_VERSION: $WINDSEND_PROJECT_VERSION"
    export WINDSEND_PROJECT_VERSION
    ./version.sh
fi

######################################################################################

# Build WindSend Rust for x86_64
WindSendRustBin_X86_64DirName="WindSend-macos-x64-S-Rust-$BUILD_TAG"
rustBinName="wind_send"
rustTarget="x86_64-apple-darwin"

cd "$WINDSEND_PROJECT_PATH" || exit
cd "$WINDSEND_RUST_PROJECT_PATH" || exit

if ! cargo build --target $rustTarget --verbose --release; then
    echo "Build x86_64 Failed!"
    exit 1
fi

mkdir -p ../bin/"$WindSendRustBin_X86_64DirName"
cp -r target/$rustTarget/release/$rustBinName ../bin/"$WindSendRustBin_X86_64DirName"
mv ../bin/"$WindSendRustBin_X86_64DirName"/$rustBinName ../bin/"$WindSendRustBin_X86_64DirName"/$WINDSEND_RUST_SERVER_BIN_NAME

cd "$WINDSEND_PROJECT_PATH" || exit
cp README.md ./bin/"$WindSendRustBin_X86_64DirName"
cp README-EN.md ./bin/"$WindSendRustBin_X86_64DirName"
cp "$WINDSEND_RUST_PROJECT_PATH/$SERVER_PROGRAM_ICON_NAME" ./bin/"$WindSendRustBin_X86_64DirName"
cd ./bin || exit
zip -r "$WindSendRustBin_X86_64DirName".zip "$WindSendRustBin_X86_64DirName"

######################################################################################

# Build WindSend for aarch64
WindSendRustBin_DirName="WindSend-macos-arm64-S-Rust-$BUILD_TAG"
rustBinName="wind_send"
rustTarget="aarch64-apple-darwin"

cd "$WINDSEND_PROJECT_PATH" || exit
cd "$WINDSEND_RUST_PROJECT_PATH" || exit

if ! cargo build --target $rustTarget --verbose --release; then
    echo "Build aarch64 Failed!"
    exit 1
fi

mkdir -p ../bin/"$WindSendRustBin_DirName"
cp -r target/$rustTarget/release/$rustBinName ../bin/"$WindSendRustBin_DirName"
mv ../bin/"$WindSendRustBin_DirName"/$rustBinName ../bin/"$WindSendRustBin_DirName"/$WINDSEND_RUST_SERVER_BIN_NAME

cd "$WINDSEND_PROJECT_PATH" || exit
cp README.md ./bin/"$WindSendRustBin_DirName"
cp README-EN.md ./bin/"$WindSendRustBin_DirName"
cp "$WINDSEND_RUST_PROJECT_PATH/$SERVER_PROGRAM_ICON_NAME" ./bin/"$WindSendRustBin_DirName"
cd ./bin || exit
zip -r "$WindSendRustBin_DirName".zip "$WindSendRustBin_DirName"

######################################################################################

# .dmg 打包逻辑

# Enter the bin directory
cd "$WINDSEND_PROJECT_PATH" || exit
cd "$WINDSEND_RUST_PROJECT_PATH" || exit
cd "./bin" || exit

ICONS_PATH="${WINDSEND_PROJECT_PATH}/app_icon/macos/AppIcon.icns"
APP_NAME="WindSend"
APP_BUNDLE="${APP_NAME}.app"

# for executable files
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
# for resources like icons
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${WindSendRustBin_X86_64DirName}/${WINDSEND_RUST_SERVER_BIN_NAME}" "${APP_BUNDLE}/Contents/MacOS/"
cp "$ICONS_PATH" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
cp "../$SERVER_PROGRAM_ICON_NAME" "${APP_BUNDLE}/Contents/Resources/icon-192.png"

cat <<EOF >"${APP_BUNDLE}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${WINDSEND_RUST_SERVER_BIN_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.doraemon.windsend</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>${WINDSEND_PROJECT_VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${WINDSEND_PROJECT_VERSION}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>LSUIElement</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
EOF

RW_DMG="${APP_NAME}_temp.dmg"
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${APP_BUNDLE}" \
    -ov \
    -format UDRW \
    "${RW_DMG}"

MOUNT_POINT="/Volumes/${APP_NAME}"
hdiutil attach "${RW_DMG}" -mountpoint "${MOUNT_POINT}"

ln -s /Applications "${MOUNT_POINT}/Applications"

hdiutil detach "${MOUNT_POINT}"
hdiutil convert "${RW_DMG}" -format UDZO -o "${WindSendRustBin_X86_64DirName}.dmg"
rm -f "${RW_DMG}"
rm -rf "${APP_BUNDLE}"

######################################################################################
# Press Enter to continue building WindSend Flutter for x86_64
if ! TheVariableIsTrue "$CI_RUNNING"; then
    read -rp "Press Enter to continue..."
fi

flutterX86_64DirName="WindSend-macos-x64-flutter-$BUILD_TAG"

# Build WindSend Flutter for x86_64
cd "$WINDSEND_PROJECT_PATH" || exit
cd "$WINDSEND_FLUTTER_PATH" || exit

if ! flutter build macos --release; then
    echo "Build Failed!"
    exit 0
fi

mkdir -p ../../bin/"$flutterX86_64DirName"
cp -r build/macos/Build/Products/Release/* ../../bin/"$flutterX86_64DirName"

cd "$WINDSEND_PROJECT_PATH" || exit
cp README.md ./bin/"$flutterX86_64DirName"
cp README-EN.md ./bin/"$flutterX86_64DirName"

cd ./bin || exit
zip -r "$flutterX86_64DirName".zip "$flutterX86_64DirName"
