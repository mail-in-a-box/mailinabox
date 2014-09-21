#!/bin/bash
#########################################################
# This script is intended to be run like this:
#
#   curl https://.../bootstrap.sh | sudo bash
#
#########################################################

if [ -z "$TAG" ]; then
	TAG=v0.02
fi

# Are we running as root?
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root. Did you leave out sudo?"
	exit
fi

# Go to root's home directory.
cd

# Clone the Mail-in-a-Box repository if it doesn't exist.
if [ ! -d mailinabox ]; then
	echo Installing git . . .
	apt-get -q -q install -y git

	echo Downloading Mail-in-a-Box . . .
	git clone -b $TAG --depth 1 https://github.com/mail-in-a-box/mailinabox 2> /dev/null
	cd mailinabox

# If it does exist, update it.
else
	echo Updating Mail-in-a-Box to $TAG . . .
	cd mailinabox
	git fetch
	if ! git checkout -q $TAG; then
		echo "Update failed. Did you modify something in `pwd`?"
		exit
	fi
fi

# Start setup script.
setup/start.sh

