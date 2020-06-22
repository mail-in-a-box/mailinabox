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

upstream_install() {
    local upstream_dir="$HOME/mailinabox-upstream"
    H1 "INSTALL UPSTREAM"
    [ ! -x /usr/bin/git ] && apt-get install -y -qq git
    
    if [ ! -d "$upstream_dir" ] || [ -z "$(ls -A "$upstream_dir")" ] ; then
        H2 "Cloning $MIAB_UPSTREAM_GIT"
        rm -rf "$upstream_dir"
        git clone "$MIAB_UPSTREAM_GIT" "$upstream_dir"
        if [ $? -ne 0 ]; then
            rm -rf "$upstream_dir"
            die "git clone upstream failed!"
        fi
        if [ -z "$UPSTREAM_TAG" ]; then
            tag_from_readme "$upstream_dir/README.md"
            if [ $? -ne 0 ]; then
                rm -rf "$upstream_dir"
                die "Failed to extract TAG from $upstream_dir/README.md"
            fi
        fi
    fi

    pushd "$upstream_dir" >/dev/null
    if [ ! -z "$UPSTREAM_TAG" ]; then
        H2 "Checkout $UPSTREAM_TAG"
        git checkout "$UPSTREAM_TAG" || die "git checkout $UPSTREAM_TAG failed"
    fi

    if [ "$TRAVIS" == "true" ]; then
        # Apply a patch to setup/dns.sh so nsd will start. We must do
        # it in the script and not after setup.sh runs because part of
        # setup includes adding a new user via the management
        # interface and that's where the management daemon crashes:
        #
        # "subprocess.CalledProcessError: Command '['/usr/sbin/service', 'nsd', 'restart']' returned non-zero exit status 1"
        #
        H2 "Patching upstream setup/dns.sh for Travis-CI"
        sed -i 's|\(.*include:.*zones\.conf.*\)|cat >> /etc/nsd/nsd.conf <<EOF\n  do-ip4: yes\n  do-ip6: no\nremote-control:\n  control-enable: no\nEOF\n\n\1|' setup/dns.sh \
            || die "Couldn't patch setup/dns.sh !!"
    fi
    
    H2 "Run upstream setup"
    if ! setup/start.sh; then
        echo "$F_WARN"
        dump_file /var/log/syslog 100
        echo "$F_RESET"
        die "Upstream setup failed!"
    fi
    popd >/dev/null
    
    workaround_dovecot_sieve_bug

    H2 "Upstream info"
    echo "Code version: $(git describe)"
    echo "Migration version: $(cat "$STORAGE_ROOT/mailinabox.version")"
}


populate() {
    local pw="$(static_qa_password)"
    
    H1 "Add some Mail-in-a-Box data"
    local users=()
    users+=("betsy@$(email_domainpart "$EMAIL_ADDR"):$pw")

    local alises=()
    aliases+=("goalias@testdom.com > $(awk -F: {'print $1'} <<<"${users[0]}")")
    aliases+=("nested@testdom.com > goalias@testdom.com")

    H2 "Add users"
    if ! populate_miab_users "" "" "" "${users[@]}"
    then
        die "Unable to add users"
    fi

    H2 "Add aliases"
    if ! populate_miab_aliases "" "" "" "${aliases[@]}"
    then
        die "Unable to add aliases"
    fi
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
        populate_by_name "${1:-basic}"
        exit $?
        ;;
esac




# install basic stuff, set the hostname, time, etc
init

# if MiaB-LDAP is already migrated, do not run upstream setup
[ -e /etc/mailinabox.conf ] && . /etc/mailinabox.conf
if [ -e "$STORAGE_ROOT/mailinabox.version" ] &&
       [ $(cat "$STORAGE_ROOT/mailinabox.version") -ge 13 ]
then
    echo "Warning: MiaB-LDAP is already installed! Skipping installation of upstream"
else
    # install upstream
    upstream_install
    . /etc/mailinabox.conf
    
    # populate some data
    populate_by_name "${1:-basic}"

    # capture upstream state
    installed_state_capture "/tmp/state/upstream"
fi

# install miab-ldap and capture state
miab_ldap_install
installed_state_capture "/tmp/state/miab-ldap"

# compare states
if ! installed_state_compare "/tmp/state/upstream" "/tmp/state/miab-ldap"; then
    die "Upstream and upgraded states are different !"
fi

#
# actual verification that mail sends/receives properly is done via
# the test runner ...
#
