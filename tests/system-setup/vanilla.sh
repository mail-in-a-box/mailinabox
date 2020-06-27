#!/bin/bash

#
# setup a "plain vanilla" system from scratch
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

if array_contains remote-nextcloud "$@"; then
    H1 "Enable remote-nextcloud mod"
    enable_miab_mod "remote-nextcloud" \
        || die "Could not enable remote-nextcloud mod"
else
    disable_miab_mod "remote-nextcloud"
fi
    
# run setup to use the remote Nextcloud (doesn't need to be available)
miab_ldap_install

