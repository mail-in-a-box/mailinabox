#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


#
# setup system using backup data
#

# ensure working directory
if [ ! -d "tests/system-setup" ]; then
    echo "This script must be run from the MiaB root directory"
    exit 1
fi

# load helper scripts
. "tests/lib/all.sh" "tests/lib" || die "Could not load lib scripts"
. "tests/system-setup/setup-defaults.sh" || die "Could not load setup-defaults"
. "tests/system-setup/setup-funcs.sh" || die "Could not load setup-funcs"

# ensure running as root
if [ "$EUID" != "0" ]; then
    die "This script must be run as root (sudo)"
fi


init() {
    H1 "INIT"
    init_test_system
    init_miab_testing "$@" || die "Initialization failed"
}


# initialize test system
init "$@"


if [ $# -lt 3 ]; then
    die "usage: $0 storage-user /path/to/encrypted /path/to/secret_key /path/to/restore-dir"
fi
storage_user="$1"    # eg. "user-data"
duplicity_files="$2" # /path/to/encrypted
secret_key="$3"      # /path/to/secret_key.txt
restore_to="$4"      # eg. /home/user-data
shift; shift; shift; shift;

H1 "Restore from backup files"
tests/bin/restore_backup.sh \
    "$storage_user" \
    "$duplicity_files" \
    "$secret_key" \
    "$restore_to" \
    || die "Restore failed"


# run setup
miab_ldap_install "$@"

