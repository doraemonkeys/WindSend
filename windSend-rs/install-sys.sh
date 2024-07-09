#!/bin/bash

INSTALL_DIR="/usr/local/WindSend-RS"
SERVICE_NAME="windsend"
# EXECUTABLE_PATH="./run.sh"
EXECUTABLE_PATH="./WindSend-S-Rust"
DESCRIPTION="WindSend Rust Server"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

sudo mkdir -p "$INSTALL_DIR"
sudo chown -R "$(whoami)" "$INSTALL_DIR"

# echo "安装目录：$INSTALL_DIR"
echo -e "Install directory: ${RED}$INSTALL_DIR${NC}"

cp -r ./* "$INSTALL_DIR"

sudo bash -c "cat >/etc/systemd/system/$SERVICE_NAME.service <<EOF
[Unit]
Description=$DESCRIPTION
After=network.target

[Service]
ExecStart=$INSTALL_DIR/$(basename $EXECUTABLE_PATH)
WorkingDirectory=$INSTALL_DIR
Restart=on-failure
StandardError=syslog
SyslogIdentifier=$SERVICE_NAME
User=$(whoami)
Environment=DISPLAY=$DISPLAY

[Install]
WantedBy=multi-user.target
EOF"

sudo chmod +x "$INSTALL_DIR/$(basename $EXECUTABLE_PATH)"
sudo chmod +x $INSTALL_DIR/*.sh

sudo systemctl daemon-reload
# sudo systemctl start $SERVICE_NAME
sudo systemctl enable $SERVICE_NAME

# 启用服务
if ! sudo systemctl start $SERVICE_NAME; then
    echo -e "${RED}Failed to start the service${NC}"
    exit 1
fi

# 检查服务状态
sleep 3
if [ "$(sudo systemctl is-active $SERVICE_NAME)" == "active" ]; then
    echo -e "${GREEN}Service started successfully${NC}"
else
    echo -e "${RED}Failed to start the service, use 'journalctl -u $SERVICE_NAME -e' to view the log${NC}"
    exit 1
fi

echo -e "${GREEN}Installation completed${NC}"
