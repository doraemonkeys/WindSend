#!/bin/bash

INSTALL_DIR="$HOME/.local/WindSend-RS"
SERVICE_NAME="windsend"

read -p "This will remove all files under the installation directory $INSTALL_DIR, continue? [y/n] " -r answer
case $answer in
[Yy]) ;;
[Nn])
    echo "Uninstall canceled"
    exit 0
    ;;
*)
    echo "Invalid input"
    exit 1
    ;;
esac

systemctl --user stop $SERVICE_NAME

systemctl --user disable $SERVICE_NAME

rm "$HOME/.config/systemd/user/$SERVICE_NAME.service"
echo "Removed $HOME/.config/systemd/user/$SERVICE_NAME.service"

rm -rf "$INSTALL_DIR"

systemctl --user daemon-reload

echo "Uninstall completed"
