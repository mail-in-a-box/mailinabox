#!/bin/bash

source "ehdd/ehdd_funcs.sh" || exit 1

if [ "$1" == "" ]; then
    echo "usage: $0 <size-in-gb>"
    echo -n "  hdd image location: $EHDD_IMG"
    if [ -e "$EHDD_IMG" ]; then echo " (exists!)"; else echo ""; fi
    exit 1
elif [ "$1" == "-location" ]; then
    echo "$EHDD_IMG"
    exit 0
elif [ "$1" == "-mountpoint" ]; then
    echo "$EHDD_MOUNTPOINT"
    exit 0
fi

EHDD_SIZE_GB="$1"


if [ ! -e "$EHDD_IMG" ]; then
    echo "Creating ${EHDD_SIZE_GB}G encryped drive: $EHDD_IMG"
    let count="$EHDD_SIZE_GB * 1024"
    [ $count -eq 0 ] && echo "Invalid size" && exit 1
    apt-get -q=2 -y install cryptsetup || exit 1
    dd if=/dev/zero of="$EHDD_IMG" bs=1M count=$count || exit 1
    loop=$(find_unused_loop)
    losetup $loop "$EHDD_IMG" || exit 1
    if ! cryptsetup luksFormat $(keyfile_option) --batch-mode -i 15000 $loop; then
        losetup -d $loop
        rm -f "$EHDD_IMG"
        exit 1
    fi
    echo ""
    echo "NOTE: You will need to reenter your drive encryption password"
    cryptsetup luksOpen $(keyfile_option) $loop $EHDD_LUKS_NAME  # map device to /dev/mapper/NAME
    mke2fs -j /dev/mapper/$EHDD_LUKS_NAME
    cryptsetup luksClose $EHDD_LUKS_NAME
    losetup -d $loop
else
    echo "ERROR: $EHDD_IMG already exists!"
    exit 1
fi
