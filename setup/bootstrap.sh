#!/bin/bash
#########################################################
# This script is intended to be run like this:
#
#   curl https://dvn.pt/power-miab | sudo bash
#
#########################################################

if [ -z "$TAG" ]; then
	# Make s
	OS=`lsb_release -d | sed 's/.*:\s*//'`
	if [ "$OS" == "Debian GNU/Linux 10 (buster)" -o "$(echo $OS | grep -o 'Ubuntu 20.04')" == "Ubuntu 20.04" ]; then
		TAG=v0.46.POWER.5
	else
		echo "This script must be run on a system running Debian 10 OR Ubuntu 20.04 LTS."
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

	echo Downloading Mail-in-a-Box $TAG. . .
	git clone \
		-b $TAG --depth 1 \
		https://github.com/ddavness/power-mailinabox \
		$HOME/mailinabox \
		< /dev/null 2> /dev/null

	echo
fi

# Change directory to it.
cd $HOME/mailinabox

# Update it.
if [ "$TAG" != "`git describe --tags`" ]; then
	echo Updating Mail-in-a-Box to $TAG . . .
	git fetch --depth 1 --force --prune origin tag $TAG
	if ! git checkout -q $TAG; then
		echo "Update failed. Did you modify something in `pwd`?"
		exit 1
	fi
	echo
fi

# Start setup script.
setup/start.sh

