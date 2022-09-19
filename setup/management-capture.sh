#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


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
