#!/bin/bash

#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

#
# This setup mod script configures postfix to queue incoming messages
# into /home/user-data/mail/spool/postfix instead of the default
# /var/spool/postfix. The benefits of doing this are:
#
#   1. It will ensure nightly backups include queued, but undelivered, mail
#   2. If you maintain a separate filesystem for /home/user-data, this
#      will get the queue off the root filesystem
#
# created: 2023-10-06 author: downtownallday
#
# Install instructions
# ====================
# From the mailinabox directory, run the following commands as root:
#
#   1. setup/enmod.sh move-postfix-queue-to-user-data
#   2. run either `setup/start.sh` or `ehdd/start-encrypted.sh` (if using
#      encryption-at-rest)
#
# Removal
# =======
# From the mailinabox directory, run the following commands as root:
#
#   1. local/move-postfix-queue-to-user-data.sh remove
#   2. rm local/move-postfix-queue-to-user-data.sh`)
#

[ -e /etc/mailinabox.conf ] && source /etc/mailinabox.conf
[ -e /etc/cloudinabox.conf ] && source /etc/cloudinabox.conf
. setup/functions.sh


change_queue_directory() {
    local where="$1"
    local cur
    cur=$(/usr/sbin/postconf -p queue_directory | awk -F= '{gsub(/^ +/, "", $2); print $2}')
    if [ "$cur" = "$where" ]; then
        echo "Postfix queue directory: $cur (no change)"
        return 0
    fi
    echo "Moving postfix queue directory to $where"
    systemctl stop postfix
    rm -rf "$where"
    mkdir -p "$(dirname "$where")"
    mv "$cur" "$where"
    /usr/sbin/postconf -e "queue_directory=$where"
    systemctl start postfix
    echo "New postfix queue directory: $where (was: $cur)"
}


if [ "${1:-}" = "remove" ]; then
    change_queue_directory /var/spool/postfix
else
    if [ ! -d "$STORAGE_ROOT/mail" ]; then
        echo "Error! $STORAGE_ROOT/mail does not exist!"
        exit 1
    fi
    change_queue_directory $STORAGE_ROOT/mail/spool/postfix
fi
