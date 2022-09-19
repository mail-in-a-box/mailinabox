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
# this mod will install the latest master branch version of roundcube
#

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

echo "Installing latest Roundcube master branch"

# where webmail.sh installs roundcube
RCM_DIR=/usr/local/lib/roundcubemail

# source files of the master branch
master_zip_url="https://github.com/roundcube/roundcubemail/archive/master.zip"

# git clone url
master_git_url="https://github.com/roundcube/roundcubemail.git"
master_tag="${RC_CLONE_TAG:-master}"


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


process_zip() {
    zip="/tmp/roundcube-master.zip"
    hide_output wget -O "$zip" "$master_zip_url"

    # set working directory to /usr/local/lib
    pushd $(dirname "$RCM_DIR") >/dev/null

    # rename active installation directory (/usr/local/lib/roundcubemail)
    # to roundcubemail-master so current installation is overwritten
    # during unzip
    mv $(basename "$RCM_DIR") roundcubemail-master

    # unzip master sources, overwriting current installation
    unzip -q -o "$zip"

    # rename back to expected installation directory
    mv roundcubemail-master $(basename "$RCM_DIR")

    # remove the temp file
    rm -f "$zip"
}



process_git() {
    # set working directory to /usr/local/lib
    pushd $(dirname "$RCM_DIR") >/dev/null

    # clone to roundcubemail-master
    git clone --branch "$master_tag" --depth 1 "$master_git_url" "roundcubemail-master"

    # checkout the desired branch/ref
    cd "roundcubemail-master"
    # if [ ! -e "program/steps/login/oauth.inc" ]; then
    #     git checkout `git rev-list -n 1 --before="2020-10-02 00:00" master`
    # fi
    
    # copy and overwrite existing installation
    tar cf - . | (cd "$RCM_DIR"; tar xf -)

    # remove clone
    cd ..
    rm -rf "roundcubemail-master"    
}


process_git

# run composer to update dependencies
cd "$RCM_DIR"

# 1. install 'dist' composer.json that came with master
if [ -e "composer.json" -a ! -e "composer.json.orig" ]; then
    mv composer.json composer.json.orig
fi
if [ -e "composer.lock" -a ! -e "composer.lock.orig" ]; then
    mv composer.lock composer.lock.orig
fi
rm -f composer.json
rm -f composer.lock
cp composer.json-dist composer.json

# 2. install composer
if [ ! -e "composer.phar" ]; then
    install_composer
fi

# 3. update dependencies
php composer.phar --no-interaction --no-plugins --no-dev install
php composer.phar --no-interaction --no-plugins require "kolab/net_ldap3"

# revert working directory
popd >/dev/null

# done
echo "Roundcube sources from $master_tag branch successfully installed"

