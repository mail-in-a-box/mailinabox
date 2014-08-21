#!/bin/bash
#########################################################
# This script is intended to be run like this:
#
#   wget https://.../bootstrap.sh | sudo bash
#
#########################################################

# Are we running as root?
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root. Did you leave out sudo?"
	exit
fi

# Go to root's home directory.
cd

# Clone the Mail-in-a-Box repository if it doesn't exist.
if [ ! -d mailinabox ]; then
	echo Downloading Mail-in-a-Box . . .
	apt-get -q -q install -y git
	git clone -q --depth 1 -b master https://github.com/mail-in-a-box/mailinabox
	cd mailinabox

# If it does exist, update it.
else
	echo Updating Mail-in-a-Box . . .
	cd mailinabox
	if ! git pull -q --ff-only; then
		echo "Update failed. Did you modify something in `pwd`?"
		exit
	fi
fi

# Start setup script.
setup/start.sh
