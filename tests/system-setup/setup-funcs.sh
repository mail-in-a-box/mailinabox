

die() {
    local msg="$1"
    echo "$msg" 1>&2
    exit 1
}


H1() {
    local msg="$1"
    echo "----------------------------------------------"
    if [ ! -z "$msg" ]; then
        echo "           $msg"
        echo "----------------------------------------------"
    fi
}

H2() {
    local msg="$1"
    if [ -z "$msg" ]; then
        echo "***"
    else
        echo "*** $msg ***"
    fi
}

dump_log() {
    local log_file="$1"
    local lines="$2"
    local title="DUMP OF $log_file"
    echo ""
    echo "--------"
    echo -n "-------- $log_file"
    if [ ! -z "$lines" ]; then
        echo " (last $line lines)"
    else
        echo ""
    fi
    echo "--------"
      
    if [ ! -z "$lines" ]; then
        tail -$lines "$log_file"
    else
        cat "$log_file"
    fi
}

is_true() {
    # empty string is not true
    if [ "$1" == "true" \
              -o "$1" == "TRUE" \
              -o "$1" == "True" \
              -o "$1" == "yes" \
              -o "$1" == "YES" \
              -o "$1" == "Yes" \
              -o "$1" == "1" ]
    then
        return 0
    else
        return 1
    fi
}

is_false() {
    if is_true $@; then return 1; fi
    return 0
}

wait_for_apt() {
    local count=0
    while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        sleep 6
        let count+=1
        if [ $count -eq 1 ]; then
            echo -n "Waiting for other package manager to finish..."
        elif [ $count -gt 100 ]; then
            echo -n "FAILED"
            return 1
        else
            echo -n "${count}.."
        fi
    done
    [ $count -ge 1 ] && echo ""
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
        dump_log "/etc/mailinabox.conf"
        dump_log "/etc/hosts"
        dump_log "/etc/nsswitch.conf"
        dump_log "/etc/nsd/nsd.conf"
        dump_log "/etc/postfix/main.cf"
    fi
}


update_system_time() {
    if [ ! -x /usr/sbin/ntpdate ]; then
        wait_for_apt
        apt-get install -y -qq ntpdate || return 1
    fi
    ntpdate -s ntp.ubuntu.com && echo "System time updated"
}

update_hosts() {
    local host="$1"
    shift
    local ip
    for ip; do
        if [ ! -z "$ip" ]; then
            local line="$ip $host"
            if ! grep -F "$line" /etc/hosts 1>/dev/null; then
                echo "$line" >>/etc/hosts
            fi
        fi
    done
}

update_hosts_for_private_ip() {
    # create /etc/hosts entry for PRIVATE_IP and PRIVATE_IPV6
    # PRIMARY_HOSTNAME must already be set
    local ip4=$(source setup/functions.sh; get_default_privateip 4)
    local ip6=$(source setup/functions.sh; get_default_privateip 6)
    [ -z "$ip4" -a -z "$ip6" ] && return 1
    [ -z "$ip6" ] && ip6="::1"
    update_hosts "$PRIMARY_HOSTNAME" "$ip4" "$ip6" || return 1
}

set_system_hostname() {
    # set the system hostname to the FQDN specified or
    # PRIMARY_HOSTNAME if no FQDN was given
    local fqdn="${1:-$PRIMARY_HOSTNAME}"
    local host="$(awk -F. '{print $1}' <<< "$fqdn")"
    sed -i 's/^127\.0\.1\.1[ \t].*/127.0.1.1 '"$fqdn $host ip4-loopback/" /etc/hosts || return 1
    #hostname "$host" || return 1
    #echo "$host" > /etc/hostname
    return 0
}


install_docker() {
    if [ -x /usr/bin/docker ]; then
        echo "Docker already installed"
        return 0
    fi
    
    wait_for_apt
    apt-get install -y -qq \
            apt-transport-https \
            ca-certificates \
            curl \
            gnupg-agent \
            software-properties-common \
        || return 1
       
    wait_for_apt
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - \
        || return 2
    
    wait_for_apt
    apt-key fingerprint 0EBFCD88 || return 3
    
    wait_for_apt
    add-apt-repository -y --update "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" || return 4
    
    wait_for_apt
    apt-get install -y -qq \
            docker-ce \
            docker-ce-cli \
            containerd.io \
        || return 5
}


install_qa_prerequisites() {
    [ -z "$STORAGE_ROOT" ] \
        && echo "Error: STORAGE_ROOT not set" 1>&2 \
        && return 1

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


travis_fix_nsd() {
    if [ "$TRAVIS" != "true" ]; then
        return 0
    fi
    
    # nsd won't start on Travis-CI without the changes below: ip6 off and
    # control-enable set to no. Even though the nsd docs say the
    # default value for control-enable is no, running "nsd-checkconf -o
    # control-enable /etc/nsd/nsd.conf" returns "yes", so we explicitly
    # set it here.
    #
    # we're assuming that the "ip-address" line is the last line in the
    # "server" section of nsd.conf. if this generated file output
    # changes, the sed command below may need to be adjusted.
    sed -i 's/ip-address\(.\)\(.*\)/ip-address\1\2\n  do-ip4\1 yes\n  do-ip6\1 no\n  verbosity\1 3\nremote-control\1\n  control-enable\1 no/' /etc/nsd/nsd.conf || return 1
    cat /etc/nsd/nsd.conf
    systemctl reset-failed nsd.service || return 2
    systemctl restart nsd.service || return 3
}
