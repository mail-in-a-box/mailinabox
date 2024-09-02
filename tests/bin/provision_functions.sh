#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

# source this file
#
# requires: lx_functions.sh
#

. "$(dirname "$BASH_SOURCE")/../lib/misc.sh"


load_provision_defaults() {
    #
    # search from the current directory up for a file named
    # ".provision_defaults"
    #
    if [ -z "$PROVISION_DEFAULTS_FILE" ]; then
        PROVISION_DEFAULTS_FILE="$(pwd)/.provision_defaults"
        while [ "$PROVISION_DEFAULTS_FILE" != "/.provision_defaults" ]; do
            [ -e "$PROVISION_DEFAULTS_FILE" ] && break
            PROVISION_DEFAULTS_FILE="$(realpath -m "$PROVISION_DEFAULTS_FILE/../..")/.provision_defaults"
        done
        source "$PROVISION_DEFAULTS_FILE" || return 1
    fi
    if [ ! -e "$PROVISION_DEFAULTS_FILE" ]; then
        return 1
    fi
}


provision_start() {
    load_provision_defaults || return 1
    local base_image="${1:-$DEFAULT_LXD_IMAGE}"
    local guest_mount_path="$2"
    shift; shift
    local opts=( "$@" )

    if [ ${#opts[@]} -eq 0 ]; then
        opts=( "${DEFAULT_LXD_INST_OPTS[@]}" )
    fi

    # set these globals
    project="$(lx_guess_project_name)"
    inst="$(basename "$PWD")"
    provision_start_s="$(date +%s)"

    echo "Creating instance '$inst' from image $base_image (${opts[@]})"
    lx_launch_vm_and_wait \
        "$project" "$inst" "$base_image" "$guest_mount_path" \
        "${opts[@]}" \
        || return 1
}


provision_shell() {
    # provision_start must have been called first!
    local remote_path="/tmp/provision.sh"
    local lxc_flags="--uid 0 --gid 0 --mode 755 --create-dirs"
    if [ ! -z "$1" ]; then
        lxc --project "$project" file push "$1" "${inst}${remote_path}" $lxc_flags || return 1

    else
        local tmp=$(mktemp)
        echo "#!/bin/sh" >"$tmp"
        cat >>"$tmp"
        lxc --project "$project" file push "$tmp" "${inst}${remote_path}" $lxc_flags || return 1
        rm -f "$tmp"
    fi

    lxc --project "$project" exec "$inst" --cwd / --env PROVISION=true \
        -- "$remote_path"
}


provision_done() {
    local rc="${1:-0}"
    echo "Elapsed: $(elapsed_pretty "$provision_start_s" "$(date +%s)")"
    if [ $rc -ne 0 ]; then
        echo "Failed with code $rc"
        return 1
    else
        echo "Success!"
        return 0
    fi
}
