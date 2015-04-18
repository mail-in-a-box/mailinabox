#!/bin/bash
################################################################
#
# This script is posted on HTTPS to make first-time installation
# super simple. Download and pipe to bash, e.g.:
#
#   curl https://.../bootstrap.sh | sudo bash
#
################################################################

# What is the current version?
if [ -z "$TAG" ]; then
	TAG=v0.08
fi

# Are we running as root?
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root. Did you leave out sudo?"
	exit
fi

# Clone the Mail-in-a-Box repository if it doesn't exist.
if [ ! -d $HOME/mailinabox ]; then
	echo Installing git . . .
	DEBIAN_FRONTEND=noninteractive apt-get -q -q install -y git < /dev/null
	echo

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

# Run the upgrade script, which in turn runs the setup script.
setup/upgrade.sh $TAG

