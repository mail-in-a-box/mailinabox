#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


usage() {
    echo ""
    echo "Restore a Mail-In-A-Box or Cloud-In-A-Box user-data directory from a local backup"
    echo ""
    echo "usage: $0 <storage-user> <path-to-encrypted-dir> <path-to-secret-key.txt> [path-to-restore-to]"
    echo "  storage-user:"
    echo "     the user account that owns the miab files. eg 'user-data'"
    echo "  path-to-encrypted-dir:"
    echo "     a directory containing a copy of duplicity files to restore. These were in"
    echo "     /home/user-data/backup/encrypted on the system."
    echo ""
    echo "  path-secret-key.txt:"
    echo "     a copy of the encryption key file 'secret-key.txt' that was kept in"
    echo "     /home/user-data/backup/secret-key.txt."
    echo ""
    echo "  path-to-restore-to:"
    echo "     the directory where the restored files are placed. the default location is"
    echo "     /home/<storage-user>. FILES IN THIS DIRECTORY WILL BE REPLACED. IF THIS IS A MOUNT POINT ENTER A SUBDIRECTORY OF THE MOUNT POINT THEN MANUALLY MOVE THE FILES BACK ONE LEVEL BECAUSE DUPLICITY AUTOMATICALLY UNMOUNTS IT!"
    echo ""
    echo "If you're using encryption-at-rest, make sure it's mounted before restoring"
    echo "eg: run ehdd/mount.sh"
    echo ""
    exit 1
}

if [ $# -lt 3 ]; then
    usage
fi

if [ $EUID -ne 0 ]; then
    echo "Must be run as root" 1>&2
    exit 1
fi

storage_user="$1"
backup_files_dir="$(realpath "$2")"
secret_key_file="$3"
restore_to_dir="$(realpath "${4:-/home/$storage_user}")"


PASSPHRASE="$(cat "$secret_key_file")"
if [ $? -ne 0 ]; then
    echo "unable to access $secret_key_file" 1>&2
    exit 1
fi
export PASSPHRASE

if [ ! -d "$backup_files_dir" ]; then
    echo "Does not exist or not a directory: $backup_files_dir" 1>&2
    exit 1
fi

echo "Shutting down services"
ehdd/shutdown.sh || exit 1

if [ ! -x /usr/bin/duplicity ]; then
    apt-get install -y -qq duplicity
fi

# Ensure users and groups are created so that duplicity properly
# restores permissions.
#
# system_users format:
#    user:group:comment:homedir:shell
#
# if the user name and group of `system_users` are identical, the
# group is created, otherwise the group must already exist (see
# system_groups below, which are created before users)

if [ -e "setup/ldap.sh" ]; then
    # Mail-In-A-Box
    system_users=(
        "openldap:openldap:OpenLDAP Server Account:/var/lib/ldap:/bin/false"
        "opendkim:opendkim::/run/opendkim:/usr/sbin/nologin"
        "spampd:spampd::/nonexistent:/usr/sbin/nologin"
        "www-data:www-data:www-data:/var/www:/usr/sbin/nologin"
    )
else
    # Cloud-In-A-Box
    system_users=(
        "mysql:mysql:MySQL Server:/nonexistent:/bin/false"
        "www-data:www-data:www-data:/var/www:/usr/sbin/nologin"
    )    
fi

system_groups=(
    "ssl-cert"
)

# add system groups
idx=0
while [ $idx -lt ${#system_groups[*]} ]; do
    group="${system_groups[$idx]}"
    groupadd -fr "$group"
    let idx+=1
done

# add system users
idx=0
while [ $idx -lt ${#system_users[*]} ]; do
    user=$(awk -F: '{print $1}' <<<"${system_users[$idx]}")
    group=$(awk -F: '{print $2}' <<<"${system_users[$idx]}")
    comment=$(awk -F: '{print $3}' <<<"${system_users[$idx]}")
    homedir=$(awk -F: '{print $4}' <<<"${system_users[$idx]}")
    shellpath=$(awk -F: '{print $5}' <<<"${system_users[$idx]}")

    if ! id "$user" >/dev/null 2>&1; then
        opts="-g $group"
        if [ "$group" = "$user" ]; then
            opts="-U"
        fi
        echo "Add user $user"
        useradd --shell "$shellpath" -r -M $opts -c "$comment" -d "$homedir" "$user"
    fi
    let idx+=1
done

# add regular user STORAGE_USER
if ! id "$storage_user" >/dev/null 2>&1; then
    # ensure the storage user exists
    echo "Add user $storage_user"
    useradd -m $storage_user
    chmod o+x /home/$storage_user
fi

echo "Restoring with duplicity"
opts=""
if [ -e "$restore_to_dir" ]; then
    opts="--force"
fi
duplicity restore $opts "file://$backup_files_dir" "$restore_to_dir" 2>&1 | (
    code=0
    while read line; do
	echo "$line"
	case "$line" in
	    Error\ * )
		code=1
		;;
	esac
    done; exit $code)

codes="${PIPESTATUS[0]}${PIPESTATUS[1]}"
[ "$codes" -ne "00" ] && exit 1


#
# check that filesystem uid's/gid's mapped to actual users/groups
#
files_with_nouser="$(find "$restore_to_dir" -nouser)"
files_with_nogroup="$(find "$restore_to_dir" -nogroup)"
if [ "${files_with_nouser}${files_with_nogroup}" != "" ]; then
    echo ""
    echo "WARNING: some restored file/directory ownerships are unmatched"
    echo "They are:"
    (find "$restore_to_dir" -nouser; find "$restore_to_dir" -nogroup) | sort | uniq
fi


echo ""
echo "Restore successful"
echo ""

exit 0

