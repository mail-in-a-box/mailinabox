#!/bin/bash

. "ehdd/ehdd_funcs.sh" || exit 1

if [ ! -e "$EHDD_IMG" ]; then
    echo "No ecrypted HDD found at $EHDD_IMG, not mounting"
    exit 0
fi

if mount | grep "^/dev/mapper/$EHDD_LUKS_NAME on $EHDD_MOUNTPOINT" >/dev/null; then
    echo "$EHDD_IMG already mounted"
    exit 0
fi

loop=$(find_unused_loop)
losetup $loop "$EHDD_IMG" || exit 1
# map device to /dev/mapper/NAME
cryptsetup luksOpen $(keyfile_option) $loop $EHDD_LUKS_NAME
code=$?
if [ $code -ne 0 ]; then
    echo "luksOpen failed ($code) - is $EHDD_IMG luks formatted?"
    losetup -d $loop
    exit 1
fi

if [ ! -e "$EHDD_MOUNTPOINT" ]; then
   echo "Creating mount point directory: $EHDD_MOUNTPOINT"
   mkdir -p "$EHDD_MOUNTPOINT" || exit 1
fi
mount /dev/mapper/$EHDD_LUKS_NAME "$EHDD_MOUNTPOINT" || exit 1
echo "Success: mounted $EHDD_MOUNTPOINT"
