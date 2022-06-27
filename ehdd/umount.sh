#!/bin/bash

. "ehdd/ehdd_funcs.sh" || exit 1


if ! is_mounted; then
    # not mounted
    exit 0
fi
umount "$EHDD_MOUNTPOINT" || exit 2
cryptsetup luksClose $EHDD_LUKS_NAME
losetup -d $(find_inuse_loop)
