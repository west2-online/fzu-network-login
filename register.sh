#!/bin/bash

ACTION=$1
SCRIPT_FILENAME="network-login.sh"
SERVICE_NAME="fzu-network-login.service"
TIMER_NAME="fzu-network-login.timer"
SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME"
TIMER_PATH="/etc/systemd/system/$TIMER_NAME"
SCRIPT_DIR="$(pwd)"


register_service() {
    echo "Creating service file at $SERVICE_PATH"
    cat <<EOF > $SERVICE_PATH
[Unit]
Description=FZU Network Login Service

[Service]
Type=oneshot
ExecStart=/bin/bash $SCRIPT_DIR/$SCRIPT_FILENAME

[Install]
WantedBy=default.target
EOF

    echo "Creating timer file at $TIMER_PATH"
    cat <<EOF > $TIMER_PATH
[Unit]
Description=Run network login script every 10 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=10min
Unit=$SERVICE_NAME

[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload
    systemctl enable $TIMER_NAME
    systemctl start $TIMER_NAME
    echo "Service registered and started."
}

unregister_service() {
    systemctl stop $TIMER_NAME
    systemctl disable $TIMER_NAME
    rm $SERVICE_PATH
    rm $TIMER_PATH
    systemctl daemon-reload
    echo "Service unregistered."
}

case $ACTION in
    register)
        register_service
        ;;
    unregister)
        unregister_service
        ;;
    *)
        echo "Usage: $0 {register|unregister}"
        exit 1
        ;;
esac