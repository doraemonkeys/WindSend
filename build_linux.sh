#!/bin/bash

#shellcheck source=/dev/null
source ./env.sh
chmod +x ./*.sh
WINDSEND_RUST_SERVER_BIN_NAME="WindSend-S-Rust"
mkdir -p ./bin

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

# Build WindSend Rust for Linux x86_64
WindSendRustBin_X86_64LinuxDirName="WindSend-S-Rust-x86_64-linux"
rustBinName="wind_send"

cd "$WINDSEND_PROJECT_PATH" || exit
cd "$WINDSEND_RUST_PROJECT_PATH" || exit

cargo build --release
mkdir -p ../bin/$WindSendRustBin_X86_64LinuxDirName
cp -r target/release/$rustBinName ../bin/$WindSendRustBin_X86_64LinuxDirName
mv ../bin/$WindSendRustBin_X86_64LinuxDirName/$rustBinName ../bin/$WindSendRustBin_X86_64LinuxDirName/$WINDSEND_RUST_SERVER_BIN_NAME
cp install.sh ../bin/$WindSendRustBin_X86_64LinuxDirName
cp uninstall.sh ../bin/$WindSendRustBin_X86_64LinuxDirName

cd "$WINDSEND_PROJECT_PATH" || exit
cp README.md ./bin/$WindSendRustBin_X86_64LinuxDirName
cp README-EN.md ./bin/$WindSendRustBin_X86_64LinuxDirName
cp "$WINDSEND_RUST_PROJECT_PATH/$SERVER_PROGRAM_ICON_NAME" ./bin/$WindSendRustBin_X86_64LinuxDirName
cd ./bin || exit
zip -r $WindSendRustBin_X86_64LinuxDirName.zip $WindSendRustBin_X86_64LinuxDirName

######################################################################################

# Build WindSend for linux-musl x86_64
WindSend_Rust_Bin_X86_64_LinuxMusl_DirName="WindSend-S-Rust-x86_64-linux-musl"
Rust_Target="x86_64-unknown-linux-musl"

cd "$WINDSEND_PROJECT_PATH" || exit
cd "$WINDSEND_RUST_PROJECT_PATH" || exit

rustup target add $Rust_Target
cargo build --release --target $Rust_Target
mkdir -p ../bin/$WindSend_Rust_Bin_X86_64_LinuxMusl_DirName
cp -r target/$Rust_Target/release/$rustBinName ../bin/$WindSend_Rust_Bin_X86_64_LinuxMusl_DirName
mv ../bin/$WindSend_Rust_Bin_X86_64_LinuxMusl_DirName/$rustBinName ../bin/$WindSend_Rust_Bin_X86_64_LinuxMusl_DirName/$WINDSEND_RUST_SERVER_BIN_NAME
cp install.sh ../bin/$WindSend_Rust_Bin_X86_64_LinuxMusl_DirName
cp uninstall.sh ../bin/$WindSend_Rust_Bin_X86_64_LinuxMusl_DirName

cd "$WINDSEND_PROJECT_PATH" || exit
cp README.md ./bin/$WindSend_Rust_Bin_X86_64_LinuxMusl_DirName
cp README-EN.md ./bin/$WindSend_Rust_Bin_X86_64_LinuxMusl_DirName
cp "$WINDSEND_RUST_PROJECT_PATH/$SERVER_PROGRAM_ICON_NAME" ./bin/$WindSend_Rust_Bin_X86_64_LinuxMusl_DirName
cd ./bin || exit
zip -r $WindSend_Rust_Bin_X86_64_LinuxMusl_DirName.zip $WindSend_Rust_Bin_X86_64_LinuxMusl_DirName

######################################################################################

# Build WindSend for linux aarch64

######################################################################################

# Press Enter to continue building WindSend Flutter for Linux x86_64
if ! TheVariableIsTrue "$CI_RUNNING"; then
    read -rp "Press Enter to continue..."
fi

flutterX86_64LinuxDirName="WindSend-flutter-x86_64-linux"

# Build WindSend Flutter for Linux x86_64
cd "$WINDSEND_PROJECT_PATH" || exit
cd "$WINDSEND_FLUTTER_PATH" || exit
flutter build linux --release

mkdir -p ../../bin/$flutterX86_64LinuxDirName
cp -r build/linux/x64/release/bundle/* ../../bin/$flutterX86_64LinuxDirName

cd "$WINDSEND_PROJECT_PATH" || exit
cp README.md ./bin/$flutterX86_64LinuxDirName
cp README-EN.md ./bin/$flutterX86_64LinuxDirName

cd ./bin || exit
zip -r $flutterX86_64LinuxDirName.zip $flutterX86_64LinuxDirName
