#!/bin/bash

#shellcheck source=/dev/null
source ./env.sh

if [ -z "$WINDSEND_PROJECT_VERSION" ]; then
    read -rp "WINDSEND_PROJECT_VERSION:v" WINDSEND_PROJECT_VERSION
fi

# 修改 Cargo.toml 中的版本号 (version = "x.x.x")
backToProjectRoot
cd "$WINDSEND_RUST_PROJECT_PATH" || exit
sed -i '0,/version = "[0-9]\+\.[0-9]\+\.[0-9]\+"/s//version = "'"${WINDSEND_PROJECT_VERSION}"'"/' Cargo.toml

# 修改 main.go 中的版本号 (const ProgramVersion = "x.x.x")
backToProjectRoot
cd "$WINDSEND_GO_PROJECT_PATH" || exit
sed -i "s/const ProgramVersion = .*/const ProgramVersion = \"${WINDSEND_PROJECT_VERSION}\"/" main.go

# 修改 pubspec.yaml 中的版本号 version:
backToProjectRoot
cd "$WINDSEND_FLUTTER_PATH" || exit
sed -i "s/version: .*/version: ${WINDSEND_PROJECT_VERSION}/" pubspec.yaml
