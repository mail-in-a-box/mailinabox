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
    
    H2 "Upstream info"
    echo "Code version: $(git describe)"
    echo "Migration version: $(cat "$STORAGE_ROOT/mailinabox.version")"
}


add_data() {
    H1 "Add some Mail-in-a-Box data"
    local users=()
    users+=("betsy@$(email_domainpart "$EMAIL_ADDR")")

    local alises=()
    aliases+=("goalias@testdom.com > ${users[0]}")
    aliases+=("nested@testdom.com > goalias@testdom.com")

    local pw="$(generate_qa_password)"


    #
    # get the existing users and aliases
    #
    local current_users=() current_aliases=()
    local user alias
    if ! rest_urlencoded GET /admin/mail/users "$EMAIL_ADDR" "$EMAIL_PW" --insecure >/dev/null 2>&1; then
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
    H2 "Add users"
    for user in "${users[@]}"; do
        if array_contains "$user" "${current_users[@]}"; then
            echo "Not adding user $user: already exists"

        elif ! rest_urlencoded POST /admin/mail/users/add "$EMAIL_ADDR" "$EMAIL_PW" --insecure -- "email=$user" "password=$pw" 2>/dev/null
        then
            die "Unable to add user $user: rc=$? err=$REST_ERROR"
        else
            echo "Add: $user"
        fi
    done

    #
    # add aliases
    #
    H2 "Add aliases"
    local aliasdef
    for aliasdef in "${aliases[@]}"; do
        alias="$(awk -F'[> ]' '{print $1}' <<<"$aliasdef")"
        local forwards_to="$(sed 's/.*> *\(.*\)/\1/' <<<"$aliasdef")"
        if array_contains "$alias" "${current_aliases[@]}"; then
            echo "Not adding alias $alias: already exists"
            
        elif ! rest_urlencoded POST /admin/mail/aliases/add "$EMAIL_ADDR" "$EMAIL_PW" --insecure -- "address=$alias" "forwards_to=$forwards_to" 2>/dev/null
        then
            die "Unable to add alias $alias: rc=$? err=$REST_ERROR"
        else
            echo "Add: $aliasdef"
        fi
    done
}

capture_state() {
    # users and aliases lists
    # dns zone files
    # tls certificates: expected CN's

    local state_dir="$1"
    local info="$state_dir/info.txt"

    H1 "Capture server state to $state_dir"
    
    # nuke saved state, if any
    rm -rf "$state_dir"
    mkdir -p "$state_dir"

    # create info.json
    H2 "create info.txt"
    echo "VERSION='$(git describe --abbrev=0)'" >"$info"
    echo "MIGRATION_VERSION=$(cat "$STORAGE_ROOT/mailinabox.version")" >>"$info"

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
    for file in /etc/nsd/zones/*.signed; do
        cp "$file" "$state_dir/zones"
    done    
}

miab_ldap_install() {
    H1 "INSTALL MIAB-LDAP"
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

    H1 "COMPARE STATES: $(basename "$s1") VS $(basename "$2")"
    H2 "Users"
    # users
    output="$(diff "$s1/users.json" "$s2/users.json" 2>&1)"
    if [ $? -ne 0 ]; then
        changed="true"
        echo "USERS ARE DIFFERENT!"
        echo "$output"
    else
        echo "No change"
    fi

    H2 "Aliases"
    output="$(diff "$s1/aliases.json" "$s2/aliases.json" 2>&1)"
    if [ $? -ne 0 ]; then
        change="true"
        echo "ALIASES ARE DIFFERENT!"
        echo "$output"
    else
        echo "No change"
    fi

    H2 "DNS - zones missing"
    local zone count=0
    for zone in $(cd "$s1/zones"; ls *.signed); do
        if [ ! -e "$s2/zones/$zone" ]; then
            echo "MISSING zone: $zone"
            changed="true"
            let count+=1
        fi
    done
    echo "$count missing"

    H2 "DNS - zones added"
    count=0
    for zone in $(cd "$s2/zones"; ls *.signed); do
        if [ ! -e "$s2/zones/$zone" ]; then
            echo "ADDED zone: $zone"
            changed="true"
            let count+=1
        fi
    done
    echo "$count added"

    H2 "DNS - zones changed"
    count=0
    for zone in $(cd "$s1/zones"; ls *.signed); do
        if [ -e "$s2/zones/$zone" ]; then
            # all the signatures change if we're using self-signed certs
            local t1="/tmp/s1.$$.txt"
            local t2="/tmp/s2.$$.txt"
            awk '$4 == "RRSIG" || $4 == "NSEC3" { next; } $4 == "SOA" { print $1" "$2" "$3" "$4" "$5" "$6" "$8" "$9" "$10" "$11" "$12; next } { print $0 }' "$s1/zones/$zone" > "$t1" 
            awk '$4 == "RRSIG" || $4 == "NSEC3" { next; } $4 == "SOA" { print $1" "$2" "$3" "$4" "$5" "$6" "$8" "$9" "$10" "$11" "$12; next } { print $0 }' "$s2/zones/$zone" > "$t2" 
            output="$(diff "$t1" "$t2" 2>&1)"
            if [ $? -ne 0 ]; then
                echo "CHANGED zone: $zone"
                echo "$output"
                changed="true"
                let count+=1
            fi
        fi
    done
    echo "$count zone files had differences"

    if $changed; then
        return 1
    else
        return 0
    fi
}



if [ "$1" == "cap" ]; then
    capture_state "tests/system-setup/state/miab-ldap"
    exit $?
elif [ "$1" == "compare" ]; then
    compare_state "tests/system-setup/state/upstream" "tests/system-setup/state/miab-ldap"
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
