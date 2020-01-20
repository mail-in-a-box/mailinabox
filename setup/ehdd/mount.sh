#!/bin/bash

hdd="$(setup/ehdd/create_hdd.sh -location)"
mountpoint="$(setup/ehdd/create_hdd.sh -mountpoint)"

if [ ! -e "$hdd" ]; then
    echo "NOTE: ecrypted HDD not found at $hdd, not mounting"
    exit 0
fi

if mount | grep "^/dev/mapper/c1 on $mountpoint" >/dev/null; then
    echo "$hdd already mounted"
    exit 0
fi

losetup /dev/loop0 "$hdd" || exit 1
# map device to /dev/mapper/c1
cryptsetup luksOpen /dev/loop0 c1
code=$?
if [ $code -ne 0 ]; then
    echo "luksOpen failed ($code) - is $hdd luks formatted?"
    losetup -d /dev/loop0
    exit 1
fi

if [ ! -e "$mountpoint" ]; then
   echo "Creating mount point directory: $mountpoint"
   mkdir -p "$mountpoint" || exit 1
fi
mount /dev/mapper/c1 "$mountpoint" || exit 1
echo "Success: mounted $mountpoint"
