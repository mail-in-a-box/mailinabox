#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


# source this file

lx_project_root_dir() {
    local d="$PWD"
    while [ ${#d} -gt 1 ]; do
        if [ -e "$d/setup" ]; then
            echo "$d"
            return 0
        fi
        d="$(dirname "$d")"
    done
    return 1
}

lx_guess_project_name() {
    local d
    d="$(lx_project_root_dir)"
    [ $? -ne 0 ] && return 1
    if [ -e "$d/setup/redis.sh" ]; then
        echo "ciab"
    else
        echo "miab"
    fi
}


# get the interface with the default route (first one)
get_system_default_network_interface() {
    ip route | awk '/^default/ {printf "%s", $5; exit 0}'
}

isa_bridge_interface() {
    local interface="$1"
    if ip --oneline link show type bridge | awk -F: '{print $2}' | grep -q "^ *$interface *\$"; then
        echo "yes"
    else
        echo "no"
    fi
}

isa_wifi_device() {
    local interface="$1"
    local type
    type="$(nmcli d show "$interface" | awk '$1=="GENERAL.TYPE:" {print $2}')"
    if [ "$type" = "wifi" ]; then
        echo "yes"
    else
        echo "no"
    fi
}

# delete an instance
lx_delete() {
    local project="${1:-default}"
    local inst="$2"
    local interactive="${3:-interactive}"

    local xargs=""
    if [ "$interactive" = "interactive" ]; then
        xargs="-i"
    fi

    # only delete instance if the instance exists
    if [ "$(lxc --project "$project" list name="$inst" -c n -f csv)" = "$inst" ]; then
        lxc --project "$project" delete "$inst" -f $xargs
    fi
}


# create a virtual-machine instance and start it
lx_launch_vm() {
    local project="${1:-default}"
    local inst_name="$2"
    lx_init_vm "$@" || return 1
    lxc --project "$project" start "$inst_name" || return 1
}


# create a virtual-machine instance (stopped)
lx_init_vm() {
    local project="${1:-default}"
    local inst_name="$2"
    local image="$3"
    local mount_host="$4"  # path that you want available in guest
    local mount_guest="$5" # mountpoint in guest
    shift; shift; shift; shift; shift;

    # a storage named the same as project must exist
    #    e.g. "lxc storage create $project dir" was executed prior.

    case "${@}" in
        *bridgenet* )
            echo "Using network 'bridgenet'"
            lxc --project "$project" profile show bridgenet | sed 's/^/    /' || return 1
            ;;
    esac

    lxc --project "$project" init "$image" "$inst_name" --vm --storage "$project" "$@" || return 1

    if [ ! -z "$mount_host" -a ! -z "$mount_guest" ]; then
        echo "adding $mount_guest on $inst_name to refer to $mount_host on host as device '${project}root'"
        if [ $EUID -ne 0 ]; then
            # so that files created by root on the mount inside the
            # guest have the permissions of the current host user and
            # not root:root
            # see: https://documentation.ubuntu.com/lxd/en/latest/userns-idmap/
            local egid="$(id --group)"
            local idmap="uid $EUID 0
gid $egid 0"
            lxc --project "$project" config set "$inst_name" raw.idmap="$idmap"
        fi
        lxc --project "$project" config device add "$inst_name" "${project}root" disk source="$(realpath "$mount_host")" path="$mount_guest" || return 1
    fi
}

lx_launch_vm_and_wait() {
    local project="$1"
    local inst="$2"
    local base_image="$3"
    local mount_project_root_to="$4"
    shift; shift; shift; shift;

    # Delete existing instance, if it exists
    lx_delete "$project" "$inst" interactive || return 1

    # Create the instance (started)
    lx_launch_vm "$project" "$inst" "$base_image" "$(lx_project_root_dir)" "$mount_project_root_to" "$@" || return 1

    lx_wait_for_boot "$project" "$inst" || return 1
}


lx_output_inst_list() {
#  Pre-defined column shorthand chars:
#    4 - IPv4 address
#    6 - IPv6 address
#    a - Architecture
#    b - Storage pool
#    c - Creation date
#    d - Description
#    D - disk usage
#    e - Project name
#    l - Last used date
#    m - Memory usage
#    M - Memory usage (%)
#    n - Name
#    N - Number of Processes
#    p - PID of the instance's init process
#    P - Profiles
#    s - State
#    S - Number of snapshots
#    t - Type (persistent or ephemeral)
#    u - CPU usage (in seconds)
#    L - Location of the instance (e.g. its cluster member)
#    f - Base Image Fingerprint (short)
#    F - Base Image Fingerprint (long)
    local project="$1"
    local columns="${2:-ns46tSL}"
    local format="${3:-table}"  # csv|json|table|yaml|compact
    lxc --project "$project" list -c "$columns" -f "$format"
}

lx_output_image_list() {
#      Column shorthand chars:
#      l - Shortest image alias (and optionally number of other aliases)
#      L - Newline-separated list of all image aliases
#      f - Fingerprint (short)
#      F - Fingerprint (long)
#      p - Whether image is public
#      d - Description
#      a - Architecture
#      s - Size
#      u - Upload date
#      t - Type
    local project="$1"
    local columns="${2:-lfpdatsu}"
    local format="${3:-table}"  # csv|json|table|yaml|compact
    lxc --project "$project" image list -c "$columns" -f "$format"
}

lx_wait_for_boot() {
    local project="$1"
    local inst="$2"

    echo -n "Wait for boot "
    while ! lxc --project "$project" exec "$inst" -- ls >/dev/null 2>&1; do
        echo -n "."
        sleep 1
    done
    echo ""
    echo -n "Wait for cloud-init "
    lxc --project "$project" exec "$inst" -- cloud-init status --wait
    local rc=$?
    
    if [ $rc -eq 0 ]; then
        echo "Wait for ip address "
        local ip=""
        local count=0
        while [ $count -lt 10 ]; do
            let count+=1
            ip="$(lxc --project "$project" exec "$inst" -- hostname -I | awk '{print $1}')"
            rc=$?
            echo "  [${count}] got: $ip"
            if [ $rc -ne 0 -o "$ip" != "" ];then
                break
            fi
            sleep 5
        done
    fi
    echo ""
    return $rc
}

lx_get_ssh_identity() {
    local keydir="tests/assets/vm_keys"
    if [ "$1" != "relative" ]; then
        keydir="$(lx_project_root_dir)/$keydir"
    fi
    echo "$keydir/id_ed25519"
}

lx_get_ssh_known_hosts() {
    local id="$(lx_get_ssh_identity)"
    local known_hosts="$(dirname "$id")/known_hosts"
    echo "$known_hosts"
}

lx_remove_known_host() {
    local hostname="$1"
    local known_hosts="$(lx_get_ssh_known_hosts)"
    ssh-keygen -f "$known_hosts" -R "$hostname"
}

lx_create_ssh_identity() {
    local id="$(lx_get_ssh_identity)"
    if [ ! -e "$id" ]; then
        mkdir -p "$(dirname "$id")"
        ssh-keygen -f "$id" -C "vm key" -N "" -t ed25519
    fi
}
