#!/bin/bash
#########################################################
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

# This script is intended to be run like this:
#
# --- For a typical installation. No encryption-at-rest. No remote Nextcloud.
#
#     curl -s https://raw.githubusercontent.com/downtownallday/mailinabox-ldap/master/setup/bootstrap.sh | sudo bash
#
# --- Installation with encryption-at-rest, add ENCRYPTION_AT_REST=true.
#
#     curl -s https://raw.githubusercontent.com/downtownallday/mailinabox-ldap/master/setup/bootstrap.sh | sudo ENCRYPTION_AT_REST=true bash
#
# --- Installation using a remote Nextcloud, add REMOTE_NEXTCLOUD=true.
#
#     curl -s https://raw.githubusercontent.com/downtownallday/mailinabox-ldap/master/setup/bootstrap.sh | sudo REMOTE_NEXTCLOUD=true bash
#
#     Important: after completing setup you MUST also connect the
#     remote Nextcloud to MiaB-LDAP by copying the file
#     setup/mods.available/connect-nextcloud-to-miab.sh to the remote
#     Nextcloud system, then run it as root.
#
# REMOTE_NEXTCLOUD and/or ENCRYPTION_AT_REST only need to be specified
# once as future bootstrap setup runs will automatically detect the
# setup options already installed.
#
#########################################################

if [ -z "$TAG" ]; then
	# If a version to install isn't explicitly given as an environment
	# variable, then install the latest version. But the latest version
	# depends on the machine's version of Ubuntu. Existing users need to
	# be able to upgrade to the latest version available for that version
	# of Ubuntu to satisfy the migration requirements.
	#
	# Also, the system status checks read this script for TAG = (without the
	# space, but if we put it in a comment it would confuse the status checks!)
	# to get the latest version, so the first such line must be the one that we
	# want to display in status checks.
	#
	# Allow point-release versions of the major releases, e.g. 22.04.1 is OK.
	UBUNTU_VERSION=$( lsb_release -d | sed 's/.*:\s*//' | sed 's/\([0-9]*\.[0-9]*\)\.[0-9]/\1/' )
	if [ "$UBUNTU_VERSION" == "Ubuntu 22.04 LTS" ]; then
		# This machine is running Ubuntu 22.04, which is supported by
		# Mail-in-a-Box versions 60 and later.
		TAG=v67
	elif [ "$UBUNTU_VERSION" == "Ubuntu 18.04 LTS" ]; then
		# This machine is running Ubuntu 18.04, which is supported by
		# Mail-in-a-Box versions 0.40 through 5x.
		echo "Support is ending for Ubuntu 18.04."
		echo "Please immediately begin to migrate your data to"
		echo "a new machine running Ubuntu 22.04. See:"
		echo "https://mailinabox.email/maintenance.html#upgrade"
		TAG=v57a
	elif [ "$UBUNTU_VERSION" == "Ubuntu 14.04 LTS" ]; then
		# This machine is running Ubuntu 14.04, which is supported by
		# Mail-in-a-Box versions 1 through v0.30.
		echo "Ubuntu 14.04 is no longer supported."
		echo "The last version of Mail-in-a-Box supporting Ubuntu 14.04 will be installed."
		TAG=v0.30
	else
		echo "This script may be used only on a machine running Ubuntu 14.04, 18.04, or 22.04."
		exit 1
	fi
fi

# Are we running as root?
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root. Did you leave out sudo?"
	exit 1
fi

# Clone the Mail-in-a-Box repository if it doesn't exist.
if [ ! -d $HOME/mailinabox ]; then
	if [ ! -f /usr/bin/git ]; then
		echo Installing git . . .
		apt-get -q -q update
		DEBIAN_FRONTEND=noninteractive apt-get -q -q install -y git < /dev/null
		echo
	fi

	if [ "$SOURCE" == "" ]; then
		SOURCE=https://github.com/downtownallday/mailinabox-ldap.git
	fi

	echo Downloading Mail-in-a-Box $TAG. . .
	git clone \
		-b $TAG --depth 1 \
		$SOURCE \
		$HOME/mailinabox \
		< /dev/null 2> /dev/null

	echo
fi

# Change directory to it.
cd $HOME/mailinabox

# Update it.
if [ "$TAG" != $(git describe --always) ]; then
	echo Updating Mail-in-a-Box to $TAG . . .
	git fetch --depth 1 --force --prune origin tag $TAG
	if ! git checkout -q $TAG; then
		echo "Update failed. Did you modify something in $(pwd)?"
		exit 1
	fi
	echo
fi

# Remote Nextcloud.
if [ "${REMOTE_NEXTCLOUD:-}" = "true" ]; then
    # Enable the remote Nextcloud setup mod
    mkdir -p local
    if ! ln -sf ../setup/mods.available/remote-nextcloud.sh local/remote-nextcloud.sh; then
        echo "Unable to create the symbolic link required to enable the remote Nextcloud setup mod"
        exit 1
    fi
elif [ -e local/remote-nextcloud.sh -a "${REMOTE_NEXTCLOUD:-}" = "false" ]; then
    # Disable remote Nextcloud support - go back to the local Nextcloud
    local/remote-nextcloud.sh cleanup
    rm -f local/remote-nextcloud.sh
fi

# Encryption-at-rest.
if [ -z "${ENCRYPTION_AT_REST:-}" ]; then
    source ehdd/ehdd_funcs.sh || exit 1
    hdd_exists && ENCRYPTION_AT_REST=true
elif [ "${ENCRYPTION_AT_REST:-}" = "false" ]; then 
    source ehdd/ehdd_funcs.sh || exit 1
    if hdd_exists; then
        echo "Encryption-at-rest must be disabled manually"
        exit 1
    fi
fi

# Start setup script.
if [ "${ENCRYPTION_AT_REST:-false}" = "true" ]; then
    ehdd/start-encrypted.sh </dev/tty
else
    setup/start.sh </dev/tty
fi

