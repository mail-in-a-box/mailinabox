#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


#
# this mod will run composer on rcmcarddav to update its dependencies
#

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

echo "Updating rcmcarddav's dependencies"

# where webmail.sh installs roundcube
RCM_DIR=/usr/local/lib/roundcubemail


install_composer() {
    # https://getcomposer.org/doc/faqs/how-to-install-composer-programmatically.md
    local EXPECTED_CHECKSUM="$(wget -q -O - https://composer.github.io/installer.sig)"
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    local ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

    if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]
    then
        >&2 echo 'ERROR: Invalid installer checksum'
        rm composer-setup.php
        return 1
    fi

    php composer-setup.php --quiet
    local RESULT=$?
    rm composer-setup.php
    [ $RESULT -eq 0 ] && return 0
    return 1
}


cd "$RCM_DIR"

# install composer into root of roundcubemail
if [ ! -e "composer.phar" ]; then
    install_composer
fi

# update dependencies
cd "plugins/carddav"
../../composer.phar install --no-interaction --no-plugins --no-dev
