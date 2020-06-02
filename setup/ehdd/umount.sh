#!/bin/bash

. "setup/ehdd/ehdd_funcs.sh" || exit 1

if ! mount | grep "$EHDD_MOUNTPOINT" >/dev/null; then
    # not mounted
    exit 0
fi
umount "$EHDD_MOUNTPOINT" || exit 1
cryptsetup luksClose $EHDD_LUKS_NAME
losetup -d $(find_inuse_loop)
