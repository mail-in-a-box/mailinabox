#
# requires:
#    scripts: [ misc.sh ]

wait_for_apt() {
    # check to see if other package managers have a lock on new
    # installs, and wait for them to finish
    #
    # returns non-zero if waiting times out (currently ~600 seconds)
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

dump_file() {
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

    if [ ! -e "$log_file" ]; then
        echo "DOES NOT EXIST"
    elif [ ! -z "$lines" ]; then
        tail -$lines "$log_file"
    else
        cat "$log_file"
    fi
}

dump_file_if_exists() {
    [ ! -e "$1" ] && return
    dump_file "$@"
}

update_system_time() {
    if systemctl is-active --quiet ntp; then
        # ntpd is running and running ntpdate will fail with "the NTP
        # socket is in use"
        echo "ntpd is already running, not updating time"
        return 0
    fi
    if [ ! -x /usr/sbin/ntpdate ]; then
        echo "Installing ntpdate"
        wait_for_apt
        exec_no_output apt-get install -y ntpdate || return 1
    fi
    ntpdate ntp.ubuntu.com
}

set_system_hostname() {
    # set the system hostname to the FQDN specified or
    # PRIMARY_HOSTNAME if no FQDN was given
    local fqdn="${1:-$PRIMARY_HOSTNAME}"
    local host="$(awk -F. '{print $1}' <<< "$fqdn")"
    if ! grep '^127.0.1.1' /etc/hosts >/dev/null; then
        # add it
        echo "127.0.1.1 $fqdn $host" >> /etc/hosts || return 1
    else
        # set it
        sed -i 's/^127\.0\.1\.1[ \t].*/127.0.1.1 '"$fqdn $host ip4-loopback/" /etc/hosts || return 1
    fi
    # ensure name is resolvable
    if ! /usr/bin/getent hosts "$fqdn" >/dev/null; then
        return 2
    fi
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


exec_no_output() {
	# This function hides the output of a command unless the command
	# fails
	local of=$(mktemp)
	"$@" &> "$of"
	local code=$?

	if [ $code -ne 0 ]; then
		echo "" 1>&2
		echo "FAILED: $@" 1>&2
		echo "-----------------------------------------" 1>&2
        echo "Return code: $code" 1>&2
        echo "Output:" 1>&2
		cat "$of" 1>&2
		echo "-----------------------------------------" 1>&2
	fi

	# Remove temporary file.
	rm -f "$of"
    [ $code -ne 0 ] && return 1
	return 0
}

git_clone() {
    local REPO="$1"
    local TREEISH="$2"
    local TARGETPATH="$3"
    local OPTIONS="$4"

    if [ ! -x /usr/bin/git ]; then
        exec_no_output apt-get install -y git || return 1
    fi

    if ! array_contains "keep-existing" $OPTIONS || \
            [ ! -d "$TARGETPATH" ] || \
            [ -z "$(ls -A "$TARGETPATH")" ]
    then
        rm -rf "$TARGETPATH"
        git clone "$REPO" "$TARGETPATH"
        if [ $? -ne 0 ]; then
            rm -rf "$TARGETPATH"
            return 1
        fi
    fi

    if [ ! -z "$TREEISH" ]; then
        pushd "$TARGETPATH" >/dev/null
        git checkout "$TREEISH" || return 2
        popd >/dev/null
    fi
}
