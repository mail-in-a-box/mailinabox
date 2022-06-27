
#
# requires:
#
#   test scripts: [ lib/misc.sh, lib/system.sh, lib/color-output.sh, lib/installed-state.sh ]
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
    if ! set_system_hostname; then
        dump_file "/etc/hosts"
        die "Could not set hostname"
    fi

    # update system time
    H2 "Set system time"
    update_system_time || echo "Ignoring error..."
    
    # update package lists before installing anything
    H2 "apt-get update"
    wait_for_apt
    exec_no_output apt-get update -qq || die "apt-get update failed!"

    # upgrade packages - if we don't do this and something like bind
    # is upgraded through automatic upgrades (because maybe MiaB was
    # previously installed), it may cause problems with the rest of
    # the setup, such as with name resolution failures
    if is_false "$TRAVIS" && [ "$SKIP_SYSTEM_UPDATE" != "1" ]; then
        H2 "apt-get upgrade"
        wait_for_apt
        cp /var/log/apt/history.log /tmp/history.log \
           || die "Unable to copy /var/log/apt/history.log to /tmp"
        exec_no_output apt-get upgrade -y --with-new-pkgs \
            || die "apt-get upgrade failed!"
        diff /tmp/history.log /var/log/apt/history.log \
            | sed 's/^> //' \
            | awk '/^(Upgrade|Install): / { print $0 }'
        rm -f /tmp/history.log
    fi
    
    # install avahi if the system dns domain is .local - note that
    # /bin/dnsdomainname returns empty string at this point
    case "$PRIMARY_HOSTNAME" in
        *.local )
            H2 "Install avahi"
            wait_for_apt
            exec_no_output apt-get install -y avahi-daemon \
                || die "could not install avahi"
            ;;
    esac
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

    # If EHDD_KEYFILE is set, use encryption-at-rest support.  The
    # drive must be created and mounted so that our QA files can be
    # copied there.
    H2 "Encryption-at-rest"
    if [ ! -z "$EHDD_KEYFILE" ]; then
        ehdd/create_hdd.sh ${EHDD_GB} || die "create luks drive failed"
        ehdd/mount.sh || die "unable to mount luks drive"
    else
        echo "Not configured for encryption-at-rest"
    fi
    
    H2 "QA prerequisites"
    local rc=0
    
    # python3-dnspython: is used by the python scripts in 'tests' and is
    #   not installed by setup
    # also install 'jq' for json processing
    echo "Install python3-dnspython, jq, git"
    wait_for_apt
    exec_no_output apt-get install -y python3-dnspython jq git \
        || die "Unable to install setup prerequisites !!"


    # tell git our directory is safe (new requirement for git 2.35.2)
    if [ -d .git ]; then
        git config --global --add safe.directory "$(pwd)"
    fi

    # copy in pre-built MiaB-LDAP ssl files
    #   1. avoid the lengthy generation of DH params
    if ! mkdir -p $STORAGE_ROOT/ssl; then
        echo "Unable to create $STORAGE_ROOT/ssl ($?)"
        rc=1
    fi
    echo "Copy dhparams"
    if ! cp tests/assets/ssl/dh2048.pem $STORAGE_ROOT/ssl; then
        echo "Copy failed ($?)"
        rc=1
    fi
        
    # create miab_ldap.conf to specify what the Nextcloud LDAP service
    # account password will be to avoid a random one created by start.sh
    if [ ! -z "$LDAP_NEXTCLOUD_PASSWORD" ]; then
        if ! mkdir -p $STORAGE_ROOT/ldap; then
            echo "Could not create $STORAGE_ROOT/ldap"
            rc=1
        fi
        [ -e $STORAGE_ROOT/ldap/miab_ldap.conf ] && \
            echo "Warning: exists: $STORAGE_ROOT/ldap/miab_ldap.conf" 1>&2
        touch $STORAGE_ROOT/ldap/miab_ldap.conf || rc=1
        if ! grep "^LDAP_NEXTCLOUD_PASSWORD=" $STORAGE_ROOT/ldap/miab_ldap.conf >/dev/null; then
            echo "LDAP_NEXTCLOUD_PASSWORD=\"$LDAP_NEXTCLOUD_PASSWORD\"" >> $STORAGE_ROOT/ldap/miab_ldap.conf
        fi
    fi

    # process command line args
    while [ $# -gt 0 ]; do
        case "$1" in
            --qa-ca )
                echo "Copy certificate authority"
                shift
                if ! cp tests/assets/ssl/ca_*.pem $STORAGE_ROOT/ssl; then
                    echo "Copy failed ($?)"
                    rc=1
                fi
                ;;

            --enable-mod=* )
                local mod="$(awk -F= '{print $2}' <<<"$1")"
                shift
                echo "Enabling local mod '$mod'"
                if ! enable_miab_mod "$mod"; then
                    echo "Enabling mod '$mod' failed"
                    rc=1
                fi
                ;;

            * )
                # ignore unknown option - may be interpreted elsewhere
                shift
                ;;
        esac            
    done

    # now that we've copied our files, unmount STORAGE_ROOT if
    # encryption-at-rest was enabled
    ehdd/umount.sh
    
    return $rc
}


enable_miab_mod() {
    local name="${1}.sh"
    if [ ! -e "$LOCAL_MODS_DIR/$name" ]; then
        mkdir -p "$LOCAL_MODS_DIR"
        if ! ln -s "$(pwd)/setup/mods.available/$name" "$LOCAL_MODS_DIR/$name"
        then
            echo "Warning: copying instead of symlinking $LOCAL_MODS_DIR/$name"
            cp "setup/mods.available/$name" "$LOCAL_MODS_DIR/$name"
        fi
    fi
}

disable_miab_mod() {
    local name="${1}.sh"
    rm -f "$LOCAL_MODS_DIR/$name"
}


tag_from_readme() {
    # extract the recommended TAG from README.md
    # sets a global "TAG"
    local readme="${1:-README.md}"
    TAG="$(grep -F 'git checkout' "$readme" | sed 's/.*\(v[0123456789]*\.[0123456789]*\).*/\1/')"
    [ $? -ne 0 -o -z "$TAG" ] && return 1
    return 0
}


workaround_dovecot_sieve_bug() {
    # Workaround a bug in dovecot/sieve that causes attempted sieve
    # compilation when a compiled sieve has the same date as the
    # source file. The fialure occurs with miab-installed "spam"
    # sieve, which can't be recompiled due to the read-only /etc
    # filesystem restriction in systemd (ProtectSystem=efull is set,
    # see `systemctl cat dovecot.service`).
    sleep 1
    touch /etc/dovecot/sieve-spam.svbin
}


say_release_info() {
    H2 "Release info"
    echo "Code version: $(git describe)"
    echo "Migration version (miab): $(cat "$STORAGE_ROOT/mailinabox.version")"
    echo "Migration version (miabldap): $(cat "$STORAGE_ROOT/mailinabox-ldap.version")"
}

clone_repo_and_pushd() {
    local repo=""
    local treeish=""
    local targetdir=""
    for arg; do
        case "$arg" in
            --checkout-repo=* )
                repo=$(awk -F= '{print $2}' <<<"$arg")
                ;;
            --checkout-treeish=* | --checkout-tag=* )
                treeish=$(awk -F= '{print $2}' <<<"$arg")
                ;;
            --checkout-targetdir=* )
                targetdir=$(awk -F= '{print $2}' <<<"$arg")
                ;;
        esac
    done
    
    if [ -z "$repo" -o -z "$treeish" -o -z "$targetdir" ]; then
        return 1
    fi

    H1 "Clone release $treeish from $repo"
    git_clone \
        "$repo" \
        "$treeish" \
        "$targetdir" \
        "keep-existing" \
        || die "could not clone $repo ($treeish) to $targetdir"

    pushd "$targetdir" >/dev/null
    return 0
}


#
# install mail-in-a-box (upstream)
#
upstream_install() {
    local need_pop="no"
    if clone_repo_and_pushd "$@"; then
        need_pop="yes"
    fi
    
    H1 "MIAB UPSTEAM INSTALL [$(git describe 2>/dev/null)]"

    # ensure we're in a MiaB working directory
    if [ -e setup/ldap.sh ]; then
        die "Cannot install: the working directory is MiaB-LDAP!"
    fi
    if [ ! -e setup/start.sh ]; then
        die "Cannot install: the working directory must contain the source"
    fi
    
    if ! setup/start.sh; then
        echo "$F_WARN"
        dump_file /var/log/syslog 100
        echo "$F_RESET"
        die "Upstream setup failed!"
    fi
    
    H2 "Post-setup actions"
    workaround_dovecot_sieve_bug

    # set actual STORAGE_ROOT, STORAGE_USER, PRIVATE_IP, etc
    . /etc/mailinabox.conf || die "Could not source /etc/mailinabox.conf"
    
    H2 "miab install success"

    if [ "need_pop" = "yes" ]; then
        popd >/dev/null
    fi
       
    # populate if specified on command line
    populate_by_cli_argument "$@"
}


miab_ldap_install() {
    local need_pop="no"
    if clone_repo_and_pushd "$@"; then
        need_pop="yes"
    fi
    
    H1 "MIAB-LDAP INSTALL [$(git describe 2>/dev/null)]"
    # ensure we're in a MiaB-LDAP working directory
    if [ ! -e setup/ldap.sh ]; then
        die "Cannot install: the working directory is not MiaB-LDAP!"
    fi

    # setup/questions.sh installs the email_validator python3 module
    # but only when in interactive mode. make sure it's also installed
    # in non-interactive mode
    if [ ! -z "${NONINTERACTIVE:-}" ]; then
        echo "Install email_validator python3 module"
        wait_for_apt
        exec_no_output apt-get install -y -qq python3-pip \
            || die "Unable to install pip !"
        exec_no_output pip3 install -q "email_validator>=1.0.0" \
            || die "Unable to install email_validator !"
    fi

    H2 "Run mailinabox-ldap setup"
    # if EHDD_KEYFILE is set, use encryption-at-rest support
    if [ ! -z "$EHDD_KEYFILE" ]; then
        ehdd/start-encrypted.sh
    else
        setup/start.sh
    fi
    
    if [ $? -ne 0 ]; then
        H1 "OUTPUT OF SELECT FILES"
        dump_file "/var/log/syslog" 100
        dump_conf_files "$TRAVIS"
        H2; H2 "End"; H2
        die "MiaB-LDAP setup failed!"
    fi

    H2 "Post-setup actions"
    workaround_dovecot_sieve_bug

    # set actual STORAGE_ROOT, STORAGE_USER, PRIVATE_IP, etc
    . /etc/mailinabox.conf || die "Could not source /etc/mailinabox.conf"

    # setup changes the hostname so avahi must be restarted
    if systemctl is-active --quiet avahi-daemon; then
        systemctl restart avahi-daemon
    fi

    H2 "miab-ldap install success"

    if [ "need_pop" = "yes" ]; then
        popd >/dev/null
    fi
       
    # populate if specified on command line
    populate_by_cli_argument "$@"
}

populate_by_cli_argument() {
    # ...ignore unknown options they may be interpreted elsewhere
    local populate_names=()
    local state_dir=""
    for arg; do
        case "$arg" in
            --populate=* )
                populate_names+=( $(awk -F= '{print $2}' <<<"$arg") )
                ;;
            --capture-state=* )
                state_dir=$(awk -F= '{print $2}' <<<"$arg")
                ;;
        esac
    done

    if [ ${#populate_names} -gt 0 ]; then
        populate_by_name "${populate_names[@]}"
    fi
    if [ ! -z "$state_dir" ]; then
        installed_state_capture "$state_dir"
    fi
}

populate_by_name() {
    local populate_name
    for populate_name; do
        H1 "Populate Mail-in-a-Box ($populate_name)"
        local populate_script="tests/system-setup/populate/${populate_name}-populate.sh"
        if [ ! -e "$populate_script" ]; then
            die "Does not exist: $populate_script"
        fi
        "$populate_script" || die "Failed: $populate_script"
    done
}
