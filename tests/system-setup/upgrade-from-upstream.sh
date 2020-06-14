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


before_install() {
    H1 "INIT"
    system_init
    miab_testing_init || die "Initialization failed"
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
        if [ -z "$TAG" ]; then
            tag_from_readme "$upstream_dir/README.md"
            if [ $? -ne 0 ]; then
                rm -rf "$upstream_dir"
                die "Failed to extract TAG from $upstream_dir/README.md"
            fi
        fi
    fi

    pushd "$upstream_dir" >/dev/null
    if [ ! -z "$TAG" ]; then
        H2 "Checkout $TAG"
        git checkout "$TAG" || die "git checkout $TAG failed"
    fi
    
    H2 "Run upstream setup"
    setup/start.sh || die "Upstream setup failed!"
    popd >/dev/null
    
    H2 "Upstream info"
    echo "Code version: $(git describe)"
    echo "Migration version: $(cat "$STORAGE_ROOT/mailinabox.version")"
}


add_data() {
    H1 "Add some Mail-in-a-Box data"
    local users=()
    users+="betsy@$(email_domainpart "$EMAIL_ADDR")"

    local alises=()
    aliases+="goalias@testdom.com > ${users[0]}"
    aliases+="nested@testdom.com > goalias@testdom.com"

    local pw="$(generate_qa_password)"


    #
    # get the existing users and aliases
    #
    local current_users=() current_aliases=()
    local user alias
    if ! rest_urlencoded GET /admin/mail/users "$EMAIL_ADDR" "$EMAIL_PW" --insecure 2>/dev/null; then
        die "Unable to enumerate users: rc=$? err=$REST_ERROR"
    fi
    for user in $REST_OUTPUT; do
        current_users+=("$user")
    done

    if ! rest_urlencoded GET /admin/mail/aliases "$EMAIL_ADDR" "$EMAIL_PW" --insecure 2>/dev/null; then
        die "Unable to enumerate aliases: rc=$? err=$REST_ERROR"
    fi
    for alias in $REST_OUTPUT; do
        current_aliases+=("$alias")
    done

    
    #
    # add users
    #
    for user in "${users[@]}"; do
        if array_contains "$user" "${current_users[@]}"; then
            echo "Not adding user $user: already exists"

        elif ! rest_urlencoded POST /admin/mail/users/add "$EMAIL_ADDR" "$EMAIL_PW" --insecure -- "email=$user" "password=$pw" 2>/dev/null
        then
            die "Unable to add user $user: rc=$? err=$REST_ERROR"
        fi
    done

    #
    # add aliases
    #
    local aliasdef
    for aliasdef in "${aliases[@]}"; do
        alias="$(awk -F'[> ]' '{print $1}' <<<"$aliasdef")"
        local forwards_to="$(sed 's/.*> *\(.*\)/\1/' <<<"$aliasdef")"
        if array_contains "$alias" "${current_aliases[@]}"; then
            echo "Not adding alias $alias: already exists"
            
        elif ! rest_urlencoded POST /admin/mail/aliases/add "$EMAIL_ADDR" "$EMAIL_PW" --insecure -- "address=$alias" "forwards_to=$forwards_to" 2>/dev/null
        then 
            die "Unable to add alias $alias: rc=$? err=$REST_ERROR"
        fi
    done
}

capture_state() {
    # users and aliases lists
    # dns zone files
    # tls certificates: expected CN's

    local state_dir="$1"
    local infojson="$state_dir/info.json"

    H1 "Capture server state to $state_dir"
    
    # nuke saved state, if any
    rm -rf "$state_dir"
    mkdir -p "$state_dir"

    # create info.json
    H2 "create info.json"
    echo "VERSION='$(git describe --abbrev=0)'" >"$infojson"
    echo "MIGRATION_VERSION=$(cat "$STORAGE_ROOT/mailinabox.version")" >>"$infojson"

    # record users
    H2 "record users"
    rest_urlencoded GET "/admin/mail/users?format=json" "$EMAIL_ADDR" "$EMAIL_PW" --insecure 2>/dev/null \
        || die "Unable to get users: rc=$? err=$REST_ERROR"
    echo "$REST_OUTPUT" > "$state_dir/users.json"

    # record aliases
    H2 "record aliases"
    rest_urlencoded GET "/admin/mail/aliases?format=json" "$EMAIL_ADDR" "$EMAIL_PW" --insecure 2>/dev/null \
        || die "Unable to get aliases: rc=$? err=$REST_ERROR"
    echo "$REST_OUTPUT" > "$state_dir/aliases.json"

    # record dns config
    H2 "record dns details"
    local file
    mkdir -p "$state_dir/zones"
    for file in ls /etc/nsd/zones/*.signed; do
        cp "$file" "$state_dir/zones"
    done
    
}

miab_ldap_install() {
    # ensure we're in a MiaB-LDAP working directory
    if [ ! -e setup/ldap.sh ]; then
        die "The working directory is not MiaB-LDAP!"
    fi
    setup/start.sh -v || die "Upgrade to MiaB-LDAP failed !!!!!!"
}

compare_state() {
    local s1="$1"
    local s2="$2"
    
    local output
    local changed="false"

    H1 "COMPARE STATES $(basename "$s1") TO $(basename "$2")"
    H2 "Users"
    # users
    output="$(diff "$s1/users.json" "$s2/users.json" 2>&1)"
    if [ $? -ne 0 ]; then
        changed="true"
        echo "USERS ARE DIFFERENT!"
        echo "$output"
    else
        echo "OK"
    fi

    H2 "Aliases"
    output="$(diff "$s1/aliases.json" "$s2/aliases.json" 2>&1)"
    if [ $? -ne 0 ]; then
        change="true"
        echo "ALIASES ARE DIFFERENT!"
        echo "$output"
    else
        echo "OK"
    fi

    H2 "DNS - zones missing"
    local zone
    for zone in $(cd "$s1/zones"; ls *.signed); do
        if [ ! -e "$s2/zones/$zone" ]; then
            echo "MISSING zone: $zone"
            changed="true"
        fi
    done

    H2 "DNS - zones added"
    for zone in $(cd "$s2/zones"; ls *.signed); do
        if [ ! -e "$s2/zones/$zone" ]; then
            echo "ADDED zone: $zone"
            changed="true"
        fi
    done

    H2 "DNS - zones changed"
    for zone in $(cd "$s1/zones"; ls *.signed); do
        if [ -e "$s2/zones/$zone" ]; then
            output="$(diff "$s1/zones/$zone" "$s2/zones/$zone" 2>&1)"
            if [ $? -ne 0 ]; then
                echo "CHANGED zone: $zone"
                echo "$output"
                changed="true"
            fi
        fi
    done

    if $changed; then
        return 1
    else
        return 0
    fi
}


if [ "$1" == "c" ]; then
    capture_state "tests/system-setup/state/miab-ldap"
    exit $?
fi


# install basic stuff, set the hostname, time, etc
before_install

# if MiaB-LDAP is already migrated, do not run upstream setup
if [ -e "$STORAGE_ROOT/mailinabox.version" ] &&
       [ $(cat "$STORAGE_ROOT/mailinabox.version") -ge 13 ]
then
    echo "Warning: MiaB-LDAP is already installed! Skipping installation of upstream"
else
    # install upstream
    upstream_install
    add_data
    capture_state "tests/system-setup/state/upstream"
fi

# install miab-ldap
miab_ldap_install
capture_state "tests/system-setup/state/miab-ldap"

# compare states
if ! compare_state "tests/system-setup/state/upstream" "tests/system-setup/state/miab-ldap"; then
    die "Upstream and upgraded states are different !"
fi

#
# actual verification that mail sends/receives properly is done via
# the test runner ...
#
