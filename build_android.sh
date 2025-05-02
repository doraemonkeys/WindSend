#!/bin/bash

#shellcheck source=/dev/null
source ./env.sh
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

echo "Building Android APK..."

######################################################################################

# Press Enter to continue building WindSend Flutter for Android
if ! TheVariableIsTrue "$CI_RUNNING"; then
    read -rp "Press Enter to build WindSend Flutter for Android..."
fi

flutterAndroidName="WindSend-flutter"

cd "$WINDSEND_PROJECT_PATH" || exit
cd "$WINDSEND_FLUTTER_PATH" || exit

if ! flutter build apk --split-per-abi --release; then
    echo "Build APK Failed!"
    exit 1
fi

echo "Build APK Success!"
mv build/app/outputs/flutter-apk/app-arm64-v8a-release.apk ../../bin/$flutterAndroidName-arm64-v8a-release.apk
mv build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk ../../bin/$flutterAndroidName-armeabi-v7a-release.apk
mv build/app/outputs/flutter-apk/app-x86_64-release.apk ../../bin/$flutterAndroidName-x86_64-release.apk
