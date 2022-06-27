#!/bin/bash

# setup MiaB-LDAP by:
#    1. installing upstream MiaB
#    2. adding some data (users/aliases/etc)
#    3. upgrading to MiaB-LDAP
#
# See setup-defaults.sh for usernames and passwords.
#


usage() {
    echo "Usage: $(basename "$0")"
    echo "Install MiaB-LDAP after installing upstream MiaB"
    exit 1
}

# ensure working directory
if [ ! -d "tests/system-setup" ]; then
    echo "This script must be run from the MiaB root directory"
    exit 1
fi

# load helper scripts
. "tests/lib/all.sh" || die "Could not load lib scripts"
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




# these are for debugging/testing
case "$1" in
    capture )
        . /etc/mailinabox.conf
        installed_state_capture "/tmp/state/miab-ldap"
        exit $?
        ;;
    compare )
        . /etc/mailinabox.conf
        installed_state_compare "/tmp/state/upstream" "/tmp/state/miab-ldap"
        exit $?
        ;;
    populate )
        . /etc/mailinabox.conf
        populate_by_name "${2:-basic}"
        exit $?
        ;;
esac




# install basic stuff, set the hostname, time, etc
init "$@"

# if MiaB-LDAP is already migrated, do not run upstream setup
[ -e /etc/mailinabox.conf ] && . /etc/mailinabox.conf
if [ -e "$STORAGE_ROOT/mailinabox.version" ] &&
       [ $(cat "$STORAGE_ROOT/mailinabox.version") -ge 13 ]
then
    echo "Warning: MiaB-LDAP is already installed! Skipping installation of upstream"
else
    # install upstream
    upstream_dir="$HOME/mailinabox-upstream"
    upstream_install \
        "$@" \
        --checkout-repo="$MIAB_UPSTREAM_GIT" \
        --checkout-treeish="$UPSTREAM_TAG" \
        --checkout-targetdir="$upstream_dir" \
        --capture-state="/tmp/state/upstream"
    pushd "$upstream_dir" >/dev/null
    say_release_info
    popd >/dev/null
fi

# install miab-ldap and capture state
miab_ldap_install --capture-state="/tmp/state/miab-ldap"

# compare states
if ! installed_state_compare "/tmp/state/upstream" "/tmp/state/miab-ldap"; then
    dump_file "/tmp/state/upstream/info.txt"
    dump_file "/tmp/state/miab-ldap/info.txt"
    die "Upstream and upgraded states are different !"
fi

#
# actual verification that mail sends/receives properly is done via
# the test runner ...
#
