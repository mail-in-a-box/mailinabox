#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


if [ -s /etc/mailinabox.conf ]; then
    source /etc/mailinabox.conf
    [ $? -eq 0 ] || exit 1
else
    STORAGE_ROOT="/home/${STORAGE_USER:-user-data}"
fi

EHDD_IMG="$STORAGE_ROOT.HDD"
EHDD_MOUNTPOINT="$STORAGE_ROOT"
EHDD_LUKS_NAME="c1"


find_unused_loop() {
    losetup -f
}

find_inuse_loop() {
    losetup -l | awk "\$6 == \"$EHDD_IMG\" { print \$1 }"
}

keyfile_option() {
    if [ ! -z "$EHDD_KEYFILE" ]; then
        echo "--key-file $EHDD_KEYFILE"
    fi
}

hdd_exists() {
    [ -e "$EHDD_IMG" ] && return 0
    return 1
}

is_mounted() {
    [ ! -e "$EHDD_IMG" ] && return 1
    if mount | grep "^/dev/mapper/$EHDD_LUKS_NAME on $EHDD_MOUNTPOINT" >/dev/null; then
        # mounted
        return 0
    else
        return 1
    fi
}
