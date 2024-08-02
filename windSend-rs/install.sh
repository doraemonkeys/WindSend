#!/bin/bash

INSTALL_DIR="$HOME/.local/WindSend-RS"
SERVICE_NAME="windsend"
EXECUTABLE_PATH="./WindSend-S-Rust"
DESCRIPTION="WindSend Rust Server"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# check if already installed
if [ -d "$INSTALL_DIR" ]; then
    echo -e "${RED}Reinstalling...${NC}"
    ./uninstall.sh
fi

mkdir -p "$INSTALL_DIR"

echo -e "Install directory: ${RED}$INSTALL_DIR${NC}"

cp -r ./* "$INSTALL_DIR"

mkdir -p "$HOME/.config/systemd/user"

cat >"$HOME/.config/systemd/user/$SERVICE_NAME.service" <<EOF
[Unit]
Description=$DESCRIPTION
After=network.target

[Service]
ExecStart=$INSTALL_DIR/$(basename $EXECUTABLE_PATH)
WorkingDirectory=$INSTALL_DIR
Restart=on-failure
RestartSec=5s
StartLimitIntervalSec=600s
StartLimitBurst=100
StandardError=syslog
SyslogIdentifier=$SERVICE_NAME
Environment=DISPLAY=$DISPLAY

[Install]
WantedBy=default.target
EOF

chmod +x "$INSTALL_DIR/$(basename $EXECUTABLE_PATH)"
chmod +x "$INSTALL_DIR"/*.sh

systemctl --user daemon-reload
systemctl --user enable $SERVICE_NAME

# 启用服务
if ! systemctl --user start $SERVICE_NAME; then
    echo -e "${RED}Failed to start the service${NC}"
    exit 1
fi

# 检查服务状态
sleep 3
if [ "$(systemctl --user is-active $SERVICE_NAME)" == "active" ]; then
    echo -e "${GREEN}Service started successfully${NC}"
else
    echo -e "${RED}Failed to start the service, use 'journalctl --user -u $SERVICE_NAME -e' to view the log${NC}"
    exit 1
fi

echo -e "${GREEN}Installation completed${NC}"
