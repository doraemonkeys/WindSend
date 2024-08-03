#!/bin/bash

#shellcheck source=/dev/null
source ./env.sh

# Press Enter to continue building WindSend Flutter for Android
if ! TheVariableIsTrue "$CI_RUNNING"; then
    read -rp "Press Enter to build WindSend Flutter for Android..."
fi

flutterAndroidName="WindSend-flutter"

cd "$WINDSEND_PROJECT_PATH" || exit
cd "$WINDSEND_FLUTTER_PATH" || exit

if ! flutter build apk --split-per-abi; then
    echo "Build APK Failed!"
    exit 1
fi

echo "Build APK Success!"
mv build/app/outputs/flutter-apk/app-arm64-v8a-release.apk ../../bin/$flutterAndroidName-arm64-v8a-release.apk
mv build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk ../../bin/$flutterAndroidName-armeabi-v7a-release.apk
mv build/app/outputs/flutter-apk/app-x86_64-release.apk ../../bin/$flutterAndroidName-x86_64-release.apk
