#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


# this script creates a new lxd image preloaded with software to speed
# up installation.
#
# prerequisites:
#
# tests/bin/lx_setup.sh must be run before running this script. it
# only needs to be run once, or any time the networking setup
# changes (eg. adding a new ethernet card).
#

D="$(dirname "$BASH_SOURCE")"
. "$D/../../bin/lx_functions.sh" || exit 1
. "$D/../../bin/provision_functions.sh" || exit 1


project="$(lx_guess_project_name)"
inst_mountpoint=/mailinabox
[ "$project" = "ciab" ] && inst_mountpoint=/cloudinabox
load_provision_defaults || exit 1
echo "Provision defaults loaded from: $(realpath --relative-to="$(pwd)" "$PROVISION_DEFAULTS_FILE")"

if [ -z "$1" ]; then
    imagelist=( $(<./imagelist) )
else
    imagelist=( "$@" )
fi


for base_image in "${imagelist[@]}"
do
    new_image="preloaded-${base_image/:/-}"
    inst_name="preloaded"

    echo ""
    echo "START: create $new_image using base image $base_image"
    echo "Delete existing instance: $inst_name"
    lx_delete "$project" "$inst_name" "no-interactive" || exit 1

    echo "Create instance '$inst_name' from '$base_image'"

    # cloud init configuration creates user 'vmuser' instead of 'ubuntu'
    cloud_config_users="#cloud-config
users:
  - default
  - name: vmuser
    gecos: VM user for ssh
    primary_group: vmuser
    groups: adm, sudo, lxd
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true
    ssh_authorized_keys:
      - $(< $(lx_get_ssh_identity).pub)
"
    lx_launch_vm "$project" "$inst_name" "$base_image" "$(lx_project_root_dir)" "$inst_mountpoint" "${DEFAULT_LXD_INST_OPTS[@]}" -c cloud-init.user-data="$cloud_config_users" -c limits.cpu=2 -c limits.memory=2GiB -d root,size=30GiB || exit 1

    lx_wait_for_boot "$project" "$inst_name"


    echo ""
    echo "================================================="
    echo "Prep the VM instance"
    echo "================================================="
    lxc --project "$project" exec "$inst_name" --cwd "$inst_mountpoint" -- sudo tests/lxd/preloaded/prepvm.sh --no-dry-run || exit 1

    echo ""
    echo "================================================="
    echo "Create an image from the instance"
    echo "================================================="
    echo "Stopping instance '$inst_name'"
    lxc --project "$project" stop "$inst_name" || exit 1

    echo "Create image '$new_image' from instance '$inst_name'"
    lxc --project "$project" publish "$inst_name" "local:" --reuse --compression gzip --alias "$new_image" || exit 1  # --compression xz

    echo ""
    echo "================================================="
    echo "Image list ($project)"
    echo "================================================="
    lx_output_image_list "$project" "ld"

    echo ""
    echo "================================================="
    echo "Delete instance '$inst_name'"
    echo "================================================="
    lx_delete "$project" "$inst_name" "no-interactive"

    echo "Success"

done
