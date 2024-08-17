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
WindSendRustBin_X86_64DirName="WindSend-S-Rust-x86_64-macos"
rustBinName="wind_send"
rustTarget="x86_64-apple-darwin"

cd "$WINDSEND_PROJECT_PATH" || exit
cd "$WINDSEND_RUST_PROJECT_PATH" || exit

if ! cargo build --target $rustTarget --verbose --release; then
    echo "Build x86_64 Failed!"
    exit 1
fi

mkdir -p ../bin/$WindSendRustBin_X86_64DirName
cp -r target/$rustTarget/release/$rustBinName ../bin/$WindSendRustBin_X86_64DirName
mv ../bin/$WindSendRustBin_X86_64DirName/$rustBinName ../bin/$WindSendRustBin_X86_64DirName/$WINDSEND_RUST_SERVER_BIN_NAME

cd "$WINDSEND_PROJECT_PATH" || exit
cp README.md ./bin/$WindSendRustBin_X86_64DirName
cp README-EN.md ./bin/$WindSendRustBin_X86_64DirName
cp "$WINDSEND_RUST_PROJECT_PATH/$SERVER_PROGRAM_ICON_NAME" ./bin/$WindSendRustBin_X86_64DirName
cd ./bin || exit
zip -r $WindSendRustBin_X86_64DirName.zip $WindSendRustBin_X86_64DirName

######################################################################################

# Build WindSend for aarch64
WindSendRustBin_X86_64DirName="WindSend-S-Rust-arm64-macos"
rustBinName="wind_send"
rustTarget="aarch64-apple-darwin"

cd "$WINDSEND_PROJECT_PATH" || exit
cd "$WINDSEND_RUST_PROJECT_PATH" || exit

if ! cargo build --target $rustTarget --verbose --release; then
    echo "Build aarch64 Failed!"
    exit 1
fi

mkdir -p ../bin/$WindSendRustBin_X86_64DirName
cp -r target/$rustTarget/release/$rustBinName ../bin/$WindSendRustBin_X86_64DirName
mv ../bin/$WindSendRustBin_X86_64DirName/$rustBinName ../bin/$WindSendRustBin_X86_64DirName/$WINDSEND_RUST_SERVER_BIN_NAME

cd "$WINDSEND_PROJECT_PATH" || exit
cp README.md ./bin/$WindSendRustBin_X86_64DirName
cp README-EN.md ./bin/$WindSendRustBin_X86_64DirName
cp "$WINDSEND_RUST_PROJECT_PATH/$SERVER_PROGRAM_ICON_NAME" ./bin/$WindSendRustBin_X86_64DirName
cd ./bin || exit
zip -r $WindSendRustBin_X86_64DirName.zip $WindSendRustBin_X86_64DirName

######################################################################################
# Press Enter to continue building WindSend Flutter for x86_64
if ! TheVariableIsTrue "$CI_RUNNING"; then
    read -rp "Press Enter to continue..."
fi

flutterX86_64DirName="WindSend-flutter-x86_64-macos"

# Build WindSend Flutter for x86_64
cd "$WINDSEND_PROJECT_PATH" || exit
cd "$WINDSEND_FLUTTER_PATH" || exit

if ! flutter build macos --release; then
    echo "Build Failed!"
    exit 0
fi

mkdir -p ../../bin/$flutterX86_64DirName
cp -r build/macos/Build/Products/Release/* ../../bin/$flutterX86_64DirName

cd "$WINDSEND_PROJECT_PATH" || exit
cp README.md ./bin/$flutterX86_64DirName
cp README-EN.md ./bin/$flutterX86_64DirName

cd ./bin || exit
zip -r $flutterX86_64DirName.zip $flutterX86_64DirName
