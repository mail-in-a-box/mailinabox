#!/bin/bash
#########################################################
# This script is intended to be run like this:
#
#   curl https://dvn.pt/power-miab | sudo bash
#
#########################################################

if [ -z "$TAG" ]; then
	# If a version to install isn't explicitly given as an environment
	# variable, then install the latest version. But the latest version
	# depends on the operating system. Existing Ubuntu 14.04 users need
	# to be able to upgrade to the latest version supporting Ubuntu 14.04,
	# in part because an upgrade is required before jumping to Ubuntu 18.04.
	# New users on Ubuntu 18.04 need to get the latest version number too.
	#
	# Also, the system status checks read this script for TAG = (without the
	# space, but if we put it in a comment it would confuse the status checks!)
	# to get the latest version, so the first such line must be the one that we
	# want to display in status checks.
	if [ "`lsb_release -d | sed 's/.*:\s*//' `" == "Debian GNU/Linux 10 (buster)" ]; then
		# This machine is running Ubuntu 18.04.
		TAG=v0.44.POWER.2

	else
		echo "This script must be run on a system running Debian 10."
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
		DEBIAN_FRONTEND=noninteractive apt-get -q -q install -y git locales < /dev/null
		echo
	fi

	echo Setting locales . . .
	locale-gen en_US.UTF-8
	echo "LANG=en_US.UTF-8" > /etc/default/locale

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
if [ "$TAG" != `git describe` ]; then
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

