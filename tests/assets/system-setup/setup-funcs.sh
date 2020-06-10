
die() {
    local msg="$1"
    echo "$msg" 1>&2
    exit 1
}

H1() {
    local msg="$1"
    echo "----------------------------------------------"
    echo "           $msg"
    echo "----------------------------------------------"
}

H2() {
    local msg="$1"
    echo "*** $msg ***"
}

install_qa_prerequisites() {
    # python3-dnspython: is used by the python scripts in 'tests' and is
    #   not installed by setup
    # ntpdate: is used by this script
    apt-get install -y \
            ntpdate \
            python3-dnspython
}

update_system_time() {
    ntpdate -s ntp.ubuntu.com && echo "System time updated"
}

update_hosts() {
    local host="$1"
    local ip="$2"
    local line="$ip $host"
    if ! grep -F "$line" /etc/hosts 1>/dev/null; then
        echo "$line" >>/etc/hosts
    fi
}

update_hosts_for_private_ip() {
    # create /etc/hosts entry for PRIVATE_IP
    # PRIMARY_HOSTNAME must already be set
    local ip=$(source setup/functions.sh; get_default_privateip 4)
    [ -z "$ip" ] && return 1
    update_hosts "$PRIMARY_HOSTNAME" "$ip" || return 1
}

install_docker() {
    if [ -x /usr/bin/docker ]; then
        echo "Docker already installed"
        return 0
    fi
    
    apt-get install -y \
            apt-transport-https \
            ca-certificates \
            curl \
            gnupg-agent \
            software-properties-common \
        || return 1
       
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - \
        || return 2
    
    apt-key fingerprint 0EBFCD88 || return 3
    
    add-apt-repository -y --update "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" || return 4
    
    apt-get install -y \
            docker-ce \
            docker-ce-cli \
            containerd.io \
        || return 5
}


travis_fix_nsd() {
    if [ "$TRAVIS" != "true" ]; then
        return 0
    fi
    
    # nsd won't start on Travis-CI without the changes below: ip6 off and
    # control-enable set to no. Even though the nsd docs says the
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
