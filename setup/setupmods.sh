#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

source /etc/mailinabox.conf # load global vars
source setup/functions.sh # load our functions

run_mods() {
    MOD_COUNT=0
    if [ -d "$LOCAL_MODS_DIR" ]; then
        for mod in $(ls "$LOCAL_MODS_DIR" | grep -v '~$'); do
            mod_path="$LOCAL_MODS_DIR/$mod"
            if [ -f "$mod_path" -a -x "$mod_path" ]; then
                echo "${F_WARN}Do setup mod: $(realpath -m --no-symlinks --relative-base "$(pwd)" "$mod_path")${F_RESET}"
                "$mod_path"
                let MOD_COUNT+=1
            fi
        done
    fi
}


backup_mods() {
    local dst="$STORAGE_ROOT/setup/mods-backup.tgz"
    if [ -d "$LOCAL_MODS_DIR" -a ! -z "$(ls -A "$LOCAL_MODS_DIR" 2>/dev/null)" ]; then
        local tmp="$dst.new"
        mkdir -p "$(dirname "$dst")"
        pushd "$LOCAL_MODS_DIR" >/dev/null
        tar czf "$tmp" \
            --exclude-backups \
            --exclude-caches \
            --exclude=*/__pycache__/* \
            --exclude=*/__pycache__ \
            *
        popd >/dev/null
        rm -f "$dst"
        mv "$tmp" "$dst"
    else
        rm -f "$dst"
    fi
}


restore_mods() {
    local dst="$STORAGE_ROOT/setup/mods-backup.tgz"
    local r=0
    if [ -e "$dst" -a ! -d "$LOCAL_MODS_DIR" ]; then
        mkdir -p "$LOCAL_MODS_DIR"
        pushd "$LOCAL_MODS_DIR" >/dev/null
        tar xzf "$dst"
        popd >/dev/null
        return 0
    fi
    return 1
}



if restore_mods; then
    echo "${F_WARN}Restore setup mods from user-data backup${F_RESET}"
fi

run_mods
if [ $MOD_COUNT -eq 0 ]; then
    echo "No setup mods are enabled. To customize setup, please see setup/mods.available/README.md"
fi

backup_mods

