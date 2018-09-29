#!/bin/bash
#########################################################
# This script is intended to be run like this:
#
#   wget https://mailinabox.email/setup.sh -qO - | sudo bash -s
#   curl -s https://mailinabox.email/setup.sh | sudo bash -s
#
#########################################################

if [ -z "$TAG" ]; then
	TAG=v0.28
fi

if [[ "$#" -ne 0 ]]; then
	echo "Usage: \"wget https://mailinabox.email/setup.sh -qO - | sudo bash -s\" or \"curl -s https://mailinabox.email/setup.sh | sudo bash -s\"" >&2
	exit 1
fi

# Are we running as root?
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root. Did you leave out sudo?" >&2
	exit 1
fi

# Check if on Linux
if ! echo "$OSTYPE" | grep -iq "linux"; then
	echo "Error: This script must be run on Linux." >&2
	exit 1
fi

# Check connectivity
if ! ping -q -c 3 mailinabox.email > /dev/null 2>&1; then
	echo "Error: Could not reach mailinabox.email, please check your internet connection and run this script again." >&2
	exit 1
fi

# Clone the Mail-in-a-Box repository if it doesn't exist.
if [ ! -d "$HOME/mailinabox" ]; then
	if [ ! -f /usr/bin/git ]; then
		echo "Installing git . . ."
		apt-get -qq update
		DEBIAN_FRONTEND=noninteractive apt-get -yqq install git < /dev/null
		echo
	fi

	echo "Downloading Mail-in-a-Box $TAG. . ."
	git clone \
		-b $TAG --depth 1 \
		https://github.com/mail-in-a-box/mailinabox \
		"$HOME/mailinabox" \
		< /dev/null

	echo
fi

# Change directory to it.
cd "$HOME/mailinabox"

# Update it.
if [ "$TAG" != "$(git describe)" ]; then
	echo "Updating Mail-in-a-Box to $TAG . . ."
	git fetch --depth 1 --force --prune origin tag $TAG
	if ! git checkout -q $TAG; then
		echo "Update failed. Did you modify something in $(pwd)?" >&2
		exit 1
	fi
	echo
fi

# Start setup script.
setup/start.sh

