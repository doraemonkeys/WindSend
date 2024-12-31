#!/bin/bash

WINDSEND_PROJECT_PATH=$(pwd)
export WINDSEND_PROJECT_PATH
function backToProjectRoot() {
    cd "$WINDSEND_PROJECT_PATH" || exit
}

TheVariableIsTrue() {
    local var="$1"
    if [[ "${var,,}" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

export WINDSEND_FLUTTER_PATH="./flutter/wind_send"
export WINDSEND_GO_PROJECT_PATH="./go"
export WINDSEND_RUST_PROJECT_PATH="./windSend-rs"
export SERVER_PROGRAM_ICON_NAME="icon-192.png"
BUILD_TAG=$(git tag --sort=-creatordate | head -n 1 || echo 'unknown')
export BUILD_TAG
# export CI_RUNNING="true"
