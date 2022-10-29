#!/bin/bash

. /etc/mailinabox.conf || exit 1
. setup/functions.sh

if [ -z "${1:-}" ]; then
    echo "usage: $0 <name-of-setup-mod>"
    echo "   eg: $0 remote-nextcloud"
    echo "For a list of available setup mods, see directory setup/mods.available"
    exit 1
fi

# determine the path to the mod specified and validate it
case "$1" in
    */* )
        mod_fn="$1"
        ;;
    *.sh )
        mod_fn="setup/mods.available/$1"
        ;;
    * )
        mod_fn="setup/mods.available/$1.sh"
        ;;
esac

if [ ! -e "$mod_fn" ]; then
    echo "DOES NOT EXIST: $mod_fn" 1>&2
    exit 1
elif [ ! -f "$mod_fn" ]; then
    echo "NOT A FILE: $mod_fn" 1>&2
    exit 1
elif [ ! -x "$mod_fn" ]; then
    echo "NOT EXECUTABLE: $mod_fn" 1>&2
    exit 1
fi

# create the enabled mods directory if it doesn't exist
mkdir -p "${LOCAL_MODS_DIR:-local}"

# if the mod is already enabled, we can exit now
link_fn="${LOCAL_MODS_DIR:-local}/$(basename "$mod_fn")"
if [ -s "$link_fn" -a -f "$link_fn" -a -x "$link_fn" ]; then
    echo "Setup mod '$1' already enabled ($link_fn)"
    exit 0
fi

# create the symlink
ln -sf \
    "$(realpath --relative-to="${LOCAL_MODS_DIR:-local}" "$mod_fn")" \
    "$link_fn"
echo "Setup mod '$1' enabled (created symlink: $link_fn)"
