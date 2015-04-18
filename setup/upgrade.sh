#!/bin/bash
# Updates an existing Mail-in-a-Box installation to a newer tag.
################################################################

# Are we running as root?
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root. Did you leave out sudo?"
	exit
fi

# Was a tag specified on the command line?
TAG=$1
if [ -z "$TAG" ]; then
	echo "Usage: setup/upgrade.sh TAGNAME"
	exit 1
fi

# Is Mail-in-a-Box already installed?
if [ ! -d $HOME/mailinabox ]; then
	echo Could not find your Mail-in-a-Box installation at $HOME/mailinabox.
	exit 1
fi

# Change directory to it.
cd $HOME/mailinabox

# Are we on that tag?
if [ "$TAG" == `git describe` ]; then
	echo "You already have Mail-in-a-Box $TAG. Run"
	echo "  sudo setup/start.sh"
	echo "if there are any problems."
	exit 1
fi

# Fetch that tag.
# bootstrap.sh script makes a shallow clone of our repository,
# which makes the download faster, but it also makes it harder
# to switch to a different tag. This magic combination of options
# to git seems to do the trick.
echo Updating Mail-in-a-Box to $TAG . . .
git fetch --depth 1 --force --prune origin tag $TAG

# Check that the tag exists and we're moving to a later version, not backwards.
CUR_VER_TIMESTAMP=$(git show -s --format="%ct") # commit time of HEAD
NEW_VER_TIMESTAMP=$(git show -s --format="%ct" $TAG^{tag}^{commit}) # commit time of the commit that the tag tags
if [ -z "$NEW_VER_TIMESTAMP" ]; then echo "$TAG is not a version of Mail-in-a-Box."; exit 1; fi
if [ $CUR_VER_TIMESTAMP -gt $NEW_VER_TIMESTAMP ]; then
	echo -n "$TAG is older than the version you currently have installed: "
	git describe
	exit 1
fi

# Set up a temporary GPG keyring specifically for holding the
# Mail-in-a-Box maintainer's signing key. Load the keys found
# in the Mail-in-a-Box installation path. These keys are trusted
# in so far as the user has already gotten them. On first installs,
# we just bootstrap by assuming whatever is in github is good.
KEYRING=/tmp/miab-upgrade-keyring
rm -rf $KEYRING
mkdir -p $KEYRING
for key in `find keys/ -type f`; do
	GNUPGHOME=$KEYRING gpg --import $key
done

# Prior to checking out the tag, verify that it was signed by a
# known key. gpg will return a success exit code if the tag is
# signed by any key known to gpg, whether trusted or not, which
# is why we establish a separate keyring for this purpose.
if ! GNUPGHOME=$KEYRING git verify-tag $TAG 2>&1 > /dev/null; then
	echo "$TAG was not signed by the Mail-in-a-Box authors. This could"
	echo "indicate the github repository has been compromised. Check"
	echo "https://twitter.com/mailinabox and https://mailinabox.email/"
	echo "for further instructions, although keep in mind that those"
	echo "resources could be compromised as well."
	exit 1
fi

# Clean up.
rm -rf $KEYRING

# Checkout the tag.
if ! git checkout -q $TAG; then
	echo "Update failed. Did you modify something in `pwd`?"
	exit
fi

# Start setup script.
setup/start.sh
