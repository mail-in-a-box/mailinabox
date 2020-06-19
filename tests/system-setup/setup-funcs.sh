
#
# requires:
#
#   test scripts: [ lib/misc.sh, lib/system.sh ]
#


die() {
    local msg="$1"
    echo "$msg" 1>&2
    exit 1
}


wait_for_docker_nextcloud() {
    local container="$1"
    local config_key="$2"
    echo -n "Waiting ..."
    local count=0
    while true; do
        if [ $count -ge 10 ]; then
            echo "FAILED"
            return 1
        fi
        sleep 6
        let count+=1
        if [ $(docker exec "$container" php -n -r "include 'config/config.php'; print \$CONFIG['$config_key']?'true':'false';") == "true" ]; then
            echo "ok"
            break
        fi
        echo -n "${count}..."
    done
    return 0
}


dump_conf_files() {
    local skip
    if [ $# -eq 0 ]; then
        skip="false"
    else
        skip="true"
        for item; do
            if is_true "$item"; then
                skip="false"
                break
            fi
        done
    fi
    if [ "$skip" == "false" ]; then
        dump_file "/etc/mailinabox.conf"
        dump_file_if_exists "/etc/mailinabox_mods.conf"
        dump_file "/etc/hosts"
        dump_file "/etc/nsswitch.conf"
        dump_file "/etc/resolv.conf"
        dump_file "/etc/nsd/nsd.conf"
        #dump_file "/etc/postfix/main.cf"
    fi
}



#
# Initialize the test system
#   hostname, time, apt update/upgrade, etc
#
# Errors are fatal
#
init_test_system() {
    H2 "Update /etc/hosts"
    set_system_hostname || die "Could not set hostname"

    # update system time
    H2 "Set system time"
    update_system_time || echo "Ignoring error..."
    
    # update package lists before installing anything
    H2 "apt-get update"
    wait_for_apt
    apt-get update -qq || die "apt-get update failed!"

    # upgrade packages - if we don't do this and something like bind
    # is upgraded through automatic upgrades (because maybe MiaB was
    # previously installed), it may cause problems with the rest of
    # the setup, such as with name resolution failures
    if is_false "$TRAVIS"; then
        H2 "apt-get upgrade"
        wait_for_apt
        apt-get upgrade -qq || die "apt-get upgrade failed!"
    fi
}


#
# Initialize the test system with QA prerequisites
# Anything needed to use the test runner, speed up the installation,
# etc
#
init_miab_testing() {
    [ -z "$STORAGE_ROOT" ] \
        && echo "Error: STORAGE_ROOT not set" 1>&2 \
        && return 1

    H2 "QA prerequisites"
    local rc=0
    
    # python3-dnspython: is used by the python scripts in 'tests' and is
    #   not installed by setup
    wait_for_apt
    apt-get install -y -qq python3-dnspython
    
    # copy in pre-built MiaB-LDAP ssl files
    #   1. avoid the lengthy generation of DH params
    mkdir -p $STORAGE_ROOT/ssl \
        || (echo "Unable to create $STORAGE_ROOT/ssl ($?)" && rc=1)
    cp tests/assets/ssl/dh2048.pem $STORAGE_ROOT/ssl \
        || (echo "Copy dhparams failed ($?)" && rc=1)

    # create miab_ldap.conf to specify what the Nextcloud LDAP service
    # account password will be to avoid a random one created by start.sh
    if [ ! -z "$LDAP_NEXTCLOUD_PASSWORD" ]; then
        mkdir -p $STORAGE_ROOT/ldap \
            || (echo "Could not create $STORAGE_ROOT/ldap" && rc=1)
        [ -e $STORAGE_ROOT/ldap/miab_ldap.conf ] && \
            echo "Warning: exists: $STORAGE_ROOT/ldap/miab_ldap.conf" 1>&2
        touch $STORAGE_ROOT/ldap/miab_ldap.conf || rc=1
        if ! grep "^LDAP_NEXTCLOUD_PASSWORD=" $STORAGE_ROOT/ldap/miab_ldap.conf >/dev/null; then
            echo "LDAP_NEXTCLOUD_PASSWORD=\"$LDAP_NEXTCLOUD_PASSWORD\"" >> $STORAGE_ROOT/ldap/miab_ldap.conf
        fi
    fi
    return $rc
}


enable_miab_mod() {
    local name="${1}.sh"
    if [ ! -e "local/$name" ]; then
        mkdir -p "local"
        if ! ln -s "../setup/mods.available/$name" "local/$name"
        then
            echo "Warning: copying instead of symlinking local/$name"
            cp "setup/mods.available/$name" "local/$name"
        fi
    fi
}

tag_from_readme() {
    # extract the recommended TAG from README.md
    # sets a global "TAG"
    local readme="${1:-README.md}"
    TAG="$(grep -F 'git checkout' "$readme" | sed 's/.*\(v[0123456789]*\.[0123456789]*\).*/\1/')"
    [ $? -ne 0 -o -z "$TAG" ] && return 1
    return 0
}


miab_ldap_install() {
    H1 "MIAB-LDAP INSTALL"
    # ensure we're in a MiaB-LDAP working directory
    if [ ! -e setup/ldap.sh ]; then
        die "Cannot install: the working directory is not MiaB-LDAP!"
    fi
    
    if ! setup/start.sh; then
        H1 "OUTPUT OF SELECT FILES"
        dump_file "/var/log/syslog" 100
        dump_conf_files "$TRAVIS"
        H2; H2 "End"; H2
        die "MiaB-LDAP setup/start.sh failed!"
    fi

    # set actual STORAGE_ROOT, STORAGE_USER, PRIVATE_IP, etc
    . /etc/mailinabox.conf || die "Could not source /etc/mailinabox.conf"
}


populate_by_name() {
    local populate_name="$1"

    H1 "Populate Mail-in-a-Box ($populate_name)"
    local populate_script="tests/system-setup/populate/${populate_name}-populate.sh"
    if [ ! -e "$populate_script" ]; then
        die "Does not exist: $populate_script"
    fi
    "$populate_script" || die "Failed: $populate_script"
}
