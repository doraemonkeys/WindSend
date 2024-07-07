#!/bin/bash

#shellcheck source=/dev/null
source ./env.sh

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

# flutter clean

./build_linux_x64.sh
