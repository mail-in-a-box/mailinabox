
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
