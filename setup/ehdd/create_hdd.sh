#!/bin/bash
if [ -s /etc/mailinabox.conf ]; then
    source /etc/mailinabox.conf
    [ $? -eq 0 ] || exit 1
else
    STORAGE_ROOT="/home/${STORAGE_USER:-user-data}"
fi

EHDD_IMG="$STORAGE_ROOT.HDD"
EHDD_SIZE_GB="$1"
MOUNTPOINT="$STORAGE_ROOT"

if [ "$1" == "" ]; then
    echo "usage: $0 <size-in-gb>"
    echo -n "  hdd image location: $EHDD_IMG"
    if [ -e "$EHDD_IMG" ]; then echo " (exists)"; else echo ""; fi
    exit 1
elif [ "$1" == "-location" ]; then
    echo "$EHDD_IMG"
    exit 0
elif [ "$1" == "-mountpoint" ]; then
    echo "$MOUNTPOINT"
    exit 0
fi


if [ ! -e "$EHDD_IMG" ]; then
    echo "Creating ${EHDD_SIZE_GB}G encryped drive: $EHDD_IMG"
    let count="$EHDD_SIZE_GB * 1024"
    [ $count -eq 0 ] && echo "Invalid size" && exit 1
    apt-get -q=2 -y install cryptsetup || exit 1
    dd if=/dev/zero of="$EHDD_IMG" bs=1M count=$count || exit 1
    losetup /dev/loop0 "$EHDD_IMG" || exit 1
    if ! cryptsetup luksFormat -i 15000 /dev/loop0; then
        losetup -d /dev/loop0
        rm -f "$EHDD_IMG"
        exit 1
    fi
    echo ""
    echo "NOTE: You will need to reenter your drive encryption password a number of times"
    cryptsetup luksOpen /dev/loop0 c1  # map device to /dev/mapper/c1
    mke2fs -j /dev/mapper/c1
    cryptsetup luksClose c1
    losetup -d /dev/loop0
else
    echo "$EHDD_IMG already exists..."
    exit 1
fi
