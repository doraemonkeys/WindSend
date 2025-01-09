#!/bin/bash

INSTALL_DIR="/usr/local/WindSend-RS"
SERVICE_NAME="windsend"

# 申请su
sudo echo ""

read -p "This will remove all files under the installation directory $INSTALL_DIR, continue? [y/n] " -r answer
case $answer in
[Yy])
    # echo "继续"
    ;;
[Nn])
    echo "Uninstall canceled"
    exit 0
    ;;
*)
    echo "Invalid input"
    exit 1
    ;;
esac

sudo systemctl stop $SERVICE_NAME

sudo systemctl disable $SERVICE_NAME

echo "Remove /etc/systemd/system/$SERVICE_NAME.service"
sudo rm /etc/systemd/system/$SERVICE_NAME.service
# echo "删除/etc/systemd/system/multi-user.target.wants/$SERVICE_NAME.service"
# sudo rm /etc/systemd/system/multi-user.target.wants/$SERVICE_NAME.service

sudo rm -rf "$INSTALL_DIR"

sudo systemctl daemon-reload

echo "Uninstall completed"
