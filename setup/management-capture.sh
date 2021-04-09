#!/bin/bash

source setup/functions.sh
source /etc/mailinabox.conf # load global vars

echo "Installing miabldap-capture daemon..."

conf="$STORAGE_ROOT/reporting/config.json"

if [ ! -e "$conf" ]; then
    mkdir -p $(dirname "$conf")
    cat > "$conf" <<EOF
{
    "capture": true,
    "prune_policy": {
        "frequency_min": 2400,
        "older_than_days": 30
    },
    "drop_disposition": {
        "failed_login_attempt": false,
        "suspected_scanner": false,
        "reject": false
    }
}
EOF
fi

sed "s|%BIN%|$(pwd)|g" conf/miabldap-capture.service > /etc/systemd/system/miabldap-capture.service

hide_output systemctl daemon-reload
hide_output systemctl enable miabldap-capture
restart_service miabldap-capture
