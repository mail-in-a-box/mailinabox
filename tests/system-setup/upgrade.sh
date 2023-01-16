#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


# setup MiaB-LDAP by:
#    1. installing a prior version of MiaB-LDAP
#    2. adding some data (users/aliases/etc)
#    3. upgrading to master branch version of MiaB-LDAP
#
# See setup-defaults.sh for usernames and passwords
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


# install basic stuff, set the hostname, time, etc
init "$@"

# install tagged release
release_dir="$HOME/miabldap_$MIABLDAP_RELEASE_TAG"
miab_ldap_install \
    "$@" \
    --checkout-repo="$MIABLDAP_GIT" \
    --checkout-treeish="$MIABLDAP_RELEASE_TAG" \
    --checkout-targetdir="$release_dir" \
    --capture-state="/tmp/state/release"

pushd "$release_dir" >/dev/null
say_release_info
popd >/dev/null

# install master miab-ldap and capture state
H2 "New miabldap"
miab_ldap_install --capture-state="/tmp/state/master"

# compare states
if ! installed_state_compare "/tmp/state/release" "/tmp/state/master"; then
    dump_file "/tmp/state/release/info.txt"
    dump_file "/tmp/state/master/info.txt"
    die "Release $RELEASE_TAG and master states are different !"
fi

#
# actual verification that mail sends/receives properly is done via
# the test runner ...
#
