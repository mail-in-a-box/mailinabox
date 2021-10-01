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
    init_miab_testing || die "Initialization failed"
}

install_release() {
    install_dir="$1"
    H1 "INSTALL RELEASE $MIABLDAP_RELEASE_TAG"
    [ ! -x /usr/bin/git ] && apt-get install -y -qq git
    
    if [ ! -d "$install_dir" ] || [ -z "$(ls -A "$install_dir")" ] ; then
        H2 "Cloning $MIABLDAP_GIT"
        rm -rf "$install_dir"
        git clone "$MIABLDAP_GIT" "$install_dir"
        if [ $? -ne 0 ]; then
            rm -rf "$install_dir"
            die "git clone failed!"
        fi
    fi

    pushd "$install_dir" >/dev/null
    H2 "Checkout $MIABLDAP_RELEASE_TAG"
    git checkout "$MIABLDAP_RELEASE_TAG" || die "git checkout $MIABLDAP_RELEASE_TAG failed"
    
    H2 "Run setup"
    if ! setup/start.sh; then
        echo "$F_WARN"
        dump_file /var/log/syslog 100
        echo "$F_RESET"
        die "Release $RELEASE_TAG setup failed!"
    fi
    
    workaround_dovecot_sieve_bug

    H2 "Release info"
    echo "Code version: $(git describe)"
    echo "Migration version (miabldap): $(cat "$STORAGE_ROOT/mailinabox-ldap.version")"
    popd >/dev/null
}


# install basic stuff, set the hostname, time, etc
init

# install release
release_dir="$HOME/miabldap_$MIABLDAP_RELEASE_TAG"
install_release "$release_dir"
. /etc/mailinabox.conf
    
# populate some data
if [ $# -gt 0 ]; then
    populate_by_name "$@"
else
    populate_by_name "basic" "totpuser"
fi

# capture release state
installed_state_capture "/tmp/state/release" "$release_dir"

# install master miab-ldap and capture state
H2 "New miabldap"
echo "git branch: $(git branch | grep '*')"
miab_ldap_install
installed_state_capture "/tmp/state/master"

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
