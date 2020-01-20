#!/bin/bash

mountpoint="$(setup/ehdd/create_hdd.sh -mountpoint)"

if ! mount | grep "$mountpoint" >/dev/null; then
    # not mounted
    exit 0
fi
umount "$mountpoint" || exit 1
cryptsetup luksClose c1
losetup -d /dev/loop0
