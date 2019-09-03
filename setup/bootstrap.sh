#!/bin/bash
#########################################################
# This script is intended to be run like this:
#
#   curl https://mailinabox.email/setup.sh | sudo bash
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
	if [ "`lsb_release -d | sed 's/.*:\s*//' | sed 's/18\.04\.[0-9]/18.04/' `" == "Ubuntu 18.04 LTS" ]; then
		# This machine is running Ubuntu 18.04.
		TAG=v0.43

	elif [ "`lsb_release -d | sed 's/.*:\s*//' | sed 's/14\.04\.[0-9]/14.04/' `" == "Ubuntu 14.04 LTS" ]; then
		# This machine is running Ubuntu 14.04.
		echo "You are installing the last version of Mail-in-a-Box that will"
		echo "support Ubuntu 14.04. If this is a new installation of Mail-in-a-Box,"
		echo "stop now and switch to a machine running Ubuntu 18.04. If you are"
		echo "upgrading an existing Mail-in-a-Box --- great. After upgrading this"
		echo "box, please visit https://mailinabox.email for notes on how to upgrade"
		echo "to Ubuntu 18.04."
		echo ""
		TAG=v0.30

	else
		echo "This script must be run on a system running Ubuntu 18.04 or Ubuntu 14.04."
		exit
	fi
fi

# Are we running as root?
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root. Did you leave out sudo?"
	exit
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
		https://github.com/mail-in-a-box/mailinabox \
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
		exit
	fi
	echo
fi

# Start setup script.
setup/start.sh

