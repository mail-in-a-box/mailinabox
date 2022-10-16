#!/bin/bash

# starting with roundcube 1.6, the larry skin is not included with the
# official release
#
# this setup mod installs the larry skin
#
# created by: downtownallday
# to remove: delete the directory
#    /usr/local/lib/roundcubemail/skins/larry
#
# setup/webmail.sh is not using composer, we have to go through these
# hoops to manually install. if it was, we could just add the larry
# skin as a requirement to roundcube's composer.json
#

. /etc/mailinabox.conf || exit 1
. setup/functions.sh
. setup/functions-downloads.sh 

RCM_DIR=/usr/local/lib/roundcubemail
LARRY_DIR=${RCM_DIR}/skins/larry

# 1. get the version of roundcube setup installed (the file
#    roundcubemail/version is created by setup/webmail.sh)

VERSION="$(awk -F: '{print $1}' "$RCM_DIR/version")"
if [ $? -ne 0 ]; then
    echo "larry: unable to determine roundcube version from $RCM_DIR/version"
    exit 1
fi

# 2. get the version of larry currently installed

if [ -e "$LARRY_DIR/version" ]; then
    LARRY_VERSION=$(<"$LARRY_DIR/version")
else
    LARRY_VERSION="0.0"
fi

# 3. get latest version of larry supported, which is roundcube version or lower

verlte() {
    [  "$1" = "$(echo -e "$1\n$2" | sort -V | head -n1)" ]
}

LARRY_WANTED=""
larry_tags=( $(git ls-remote --tags https://github.com/roundcube/larry.git | awk '{print $2}' | awk -F/ '{print $3}' | sort --version-sort --reverse) )

for tag in ${larry_tags[*]}; do
    if verlte "$tag" "$VERSION"; then
        LARRY_WANTED="$tag"
        break
    fi
done

# 4. install if neccessary

if [ "$LARRY_VERSION" != "$LARRY_WANTED" ]; then
    echo "Installing roundcube larry skin version $LARRY_WANTED"
    install_composer
    workdir=$(mktemp -d)
    pushd "$workdir" >/dev/null
    cat > "composer.json" <<EOF
{
    "name": "mailinabox/larry",
    "description": "larry skin",
    "repositories": [
        {
            "type": "composer",
            "url": "https://plugins.roundcube.net"
        }
    ],
    "require": {
	"roundcube/larry":"~$LARRY_WANTED"
    },
    "config": {
        "allow-plugins": {
            "roundcube/plugin-installer": false
        }
    }
}
EOF
    /usr/local/bin/composer install --quiet
    rm -rf "$LARRY_DIR"
    echo -n "$LARRY_WANTED" >vendor/roundcube/larry/version
    mv vendor/roundcube/larry "$LARRY_DIR"
    popd >/dev/null
    rm -rf "$workdir"

else
    echo "Roundcube larry skin already at version $LARRY_WANTED"

fi

