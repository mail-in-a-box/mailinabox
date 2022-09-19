#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


. "ehdd/ehdd_funcs.sh" || exit 1


if ! is_mounted; then
    # not mounted
    exit 0
fi
umount "$EHDD_MOUNTPOINT" || exit 2
cryptsetup luksClose $EHDD_LUKS_NAME
losetup -d $(find_inuse_loop)
