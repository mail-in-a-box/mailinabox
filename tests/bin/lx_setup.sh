#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


#
# This script configures the system for virtulization by installing
# lxd, adding a host bridge, and configuring some firewall
# rules. Beware that the user running the script will be added to the
# 'sudo' group!
#
# The script can be run anytime, but usually only needs to be run
# once. Once successful, the lxd-based test vms can be run locally.
#
# Limitations:
#
# The host bridge only works with an ethernet interface. Wifi does not
# work, so you must be plugged in to run the vm tests.
#
# Docker cannot be installed alongside as LXD due to conflicts with
# Docker's iptables entries. More on this issue can be found here:
#
#     https://github.com/docker/for-linux/issues/103
#
#     https://documentation.ubuntu.com/lxd/en/latest/howto/network_bridge_firewalld/#prevent-connectivity-issues-with-lxd-and-docker
#
# Removal:
#
# Run the script with a single "-d" argument to back out the changes.
#
# Helpful tools:
#
# NetworkManager UI:  nm-connection-editor
# NetworkManager cli: nmcli
#

D=$(dirname "$BASH_SOURCE")
. "$D/lx_functions.sh" || exit 1

project="$(lx_guess_project_name)"
bridge_yaml="/etc/netplan/51-lxd-bridge.yaml"


install_packages() {
    sudo snap install lxd --channel=latest/stable
    if [ $EUID -ne 0 ]; then
        echo "Add $USER to the 'sudo' group (!!)"
        sudo usermod -aG sudo $USER || exit 1
    fi
}

remove_packages() {
    # note: run 'snap remove --purge lxd' to nuke lxd images,
    # otherwise they stay on the system
    snap remove lxd
}

create_network_bridge() {
    # Create network bridge (we'll bridge vms to the local network)
    # On return, sets these variables:
    #    vm_bridge: to name of bridge interface

    # get the interface with the default route (first one)
    local default_network_interface="$(get_system_default_network_interface)"
    local isa_bridge="$(isa_bridge_interface "$default_network_interface")"
    local isa_wifi_device="$(isa_wifi_device "$default_network_interface")"

    if [ "$isa_bridge" = "yes" ]; then
        vm_bridge="$default_network_interface"
        #out_iface="$(ip --oneline link show type bridge_slave | grep -F " $default_network_interface " | awk -F: '{print $2}')"
        #out_iface="$default_network_interface"

    else
        echo "NO HOST BRIDGE FOUND!!! CREATING ONE."
        
        if [ "$isa_wifi_device" = "yes" ]; then
            echo "*********************************************************"
            echo "UNSUPPORTED: Host bridging is not available with WIFI ! (interface $default_network_interface)"
            echo "*********************************************************"
            return 1
        fi
    
        echo "YOU WILL LOSE NETWORK CONNECTIVITY BRIEFLY"
        echo "To remove the host bridge, delete $bridge_yaml, then run netplan apply, or run this script with '-u'"
        vm_bridge="br-lxd0"
        #out_iface="br-lxd0"
        tmp="$(mktemp)"
        sudo cat <<EOF > "$tmp"
network:
    ethernets:
        myeths:
            match:
                name: $default_network_interface
            dhcp4: no
    bridges:
        $vm_bridge:
            dhcp4: yes
            interfaces: [ myeths ] 

EOF
        if [ -e "$bridge_yaml" ]; then
            echo "Overwriting netplan $bridge_yaml"
        else
            echo "Adding netplan $bridge_yaml"
        fi
        sudo mv "$tmp" "$bridge_yaml" || return 1
        sudo chown root:root "$bridge_yaml"
        sudo chmod 600 "$bridge_yaml"
        sudo netplan apply || return 1
    fi
}


remove_network_bridge() {
    if [ -e "$bridge_yaml" ]; then
        sudo rm -f "$bridge_yaml" || return 1
        sudo netplan apply || return 1
    else
        echo "OK: Bridge configuration does not exist ($bridge_yaml)"
    fi
}

install_ufw_rules() {
    local bridge="$1"
    # per: https://documentation.ubuntu.com/lxd/en/latest/howto/network_bridge_firewalld/
    sudo ufw allow in on "$bridge" comment 'for lxd'
    sudo ufw route allow in on "$bridge" comment 'for lxd'
    sudo ufw route allow out on "$bridge" comment 'for lxd'
    if which docker >/dev/null; then
        echo "WARNING: docker appears to be installed. Guest VM networking probably won't work as the docker iptables conflict with LXD (guest DHCP broadcasts are dropped)"
    fi
}

remove_ufw_rules() {
    # 2. Remove all old ufw rules
    sudo ufw status numbered | grep -E '(for lxd|for multipass)' | cut -c2-3 | sort -nr |
        while read n; do
            echo 'y' | sudo ufw delete $n
        done
}

create_lxd_project_and_pool() {
    local bridge="$1"
    # Create project and networking bridge profile. When an instance
    # is initialized, include the 'bridgenet' profile (see
    # lx_init_vm() in lx_functions.sh)

    echo "Create lxd project '$project' with profile 'bridgenet'"
    echo "  bridge: $bridge"
    lxc project create "$project" 2>/dev/null
    lxc --project "$project" profile create bridgenet 2>/dev/null
    cat <<EOF | lxc --project "$project" profile edit bridgenet
description: Bridged networking LXD profile
devices:
  eth0:
    name: eth0
    nictype: bridged
    parent: $bridge
    type: nic
EOF
    [ $? -ne 0 ] && return 1

    # create lxd storage pool for project (our convention is that
    # project and storage must have the same name)

    if ! lxc storage list -f csv | grep -q "^$project,"; then
        echo "Create storage pool for $project project"
        lxc storage create "$project" dir || return 1
    fi
}




if [ "$1" = "-u" ]; then
    # uninstall
    echo "Revert ufw rules"
    remove_ufw_rules
    
    echo "Remove packages"
    remove_packages
    
    echo "Remove network bridge"
    remove_network_bridge

else
    echo "Install packages"
    install_packages || exit 1

    echo "Revert ufw rules"
    remove_ufw_rules || exit 1

    echo "Create network bridge"
    create_network_bridge || exit 1   # sets vm_bridge

    echo "Install ufw rules"
    install_ufw_rules "$vm_bridge" || exit 1
    
    create_lxd_project_and_pool "$vm_bridge" || exit 1

    lx_create_ssh_identity || exit 1
fi

