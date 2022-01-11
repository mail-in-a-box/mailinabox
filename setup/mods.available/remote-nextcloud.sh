#!/bin/bash

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# maintain a separate conf file because setup rewrites mailinabox.conf
touch /etc/mailinabox_mods.conf
. /etc/mailinabox_mods.conf

# where webmail.sh installs roundcube
RCM_DIR=/usr/local/lib/roundcubemail
RCM_PLUGIN_DIR=${RCM_DIR}/plugins

# where zpush.sh installs z-push
ZPUSH_DIR=/usr/local/lib/z-push


configure_zpush() {
    # have zpush use the remote nextcloud for carddav/caldav
    # instead of the nextcloud that comes with mail-in-a-box
    
    cp setup/mods.available/conf/zpush/backend_carddav.php $ZPUSH_DIR/backend/carddav/config.php
    cp setup/mods.available/conf/zpush/backend_caldav.php $ZPUSH_DIR/backend/caldav/config.php
    local var val
    for var in NC_PROTO NC_HOST NC_PORT NC_PREFIX; do
        eval "val=\$$var"
        sed -i "s^$var^${val%/}^g" $ZPUSH_DIR/backend/carddav/config.php
        sed -i "s^$var^${val%/}^g" $ZPUSH_DIR/backend/caldav/config.php
    done    
}


configure_roundcube() {
    # replace the plugin configuration from the default Mail-In-A-Box
    local name="${1:-$NC_HOST}"
    local baseurl="$NC_PROTO://$NC_HOST:$NC_PORT$NC_PREFIX"
    
    # Configure CardDav plugin
    #
    # 1. make MiaB ownCloud contacts read-only so users can still
    #    access them, but not change them, and no sync occurs
    #
    # a. set 'active' to 'false'
    #    regular expression before "bashing" it:
    #       (['"]active['"][ \t]*=>[ \t]*)true
    #
    sed -i 's/\(['"'"'"]active['"'"'"][ \t]*=>[ \t]*\)true/\1false/' ${RCM_PLUGIN_DIR}/carddav/config.inc.php

    # b. set 'readonly' to 'true'
    #    regular expressions is like above
    sed -i 's/\(['"'"'"]readonly['"'"'"][ \t]*=>[ \t]*\)false/\1true/' ${RCM_PLUGIN_DIR}/carddav/config.inc.php

    # c. add 'rediscover_mode' => 'none'
    if ! grep -F 'rediscover_mode' ${RCM_PLUGIN_DIR}/carddav/config.inc.php >/dev/null; then
        sed -i 's/^\([ \t]*['"'"'"]readonly['"'"'"][ \t]*=>.*\)$/\1\n\t '\''rediscover_mode'\'' => '\''none'\'',/' ${RCM_PLUGIN_DIR}/carddav/config.inc.php
    fi

    #
    # 2. add the remote Nextcloud
    #
    cat >> ${RCM_PLUGIN_DIR}/carddav/config.inc.php <<EOF
<?php
/* Do not edit. Written by Mail-in-a-Box-LDAP. Regenerated on updates. */
//\$prefs['_GLOBAL']['hide_preferences'] = true;
//\$prefs['_GLOBAL']['suppress_version_warning'] = true;
\$prefs['cloud'] = array(
	 'name'         =>  '$name',
	 'username'     =>  '%u', // login username
	 'password'     =>  '%p', // login password
	 'url'          =>  '${baseurl%/}/remote.php/carddav/addressbooks/%u/contacts',
	 'active'       =>  true,
	 'readonly'     =>  false,
	 'refresh_time' => '02:00:00',
	 'fixed'        =>  array('username','password'),
	 'preemptive_auth' => '1',
	 'hide'        =>  false,
);
?>
EOF
}



remote_nextcloud_handler() {
    echo ""
    echo "============================"
    echo "Configure a remote Nextcloud"
    echo "============================"
    echo 'Enter the url or hostname and web prefix of your remote Nextcloud'
    echo 'For example:'
    echo '    "cloud.mydomain.com/" - Nextcloud server with no prefix'
    echo '    "cloud.mydomain.com"  - same as above'
    echo '    "www.mydomain.com/cloud"  - a Nextcloud server having a prefix /cloud'
    echo ''

    local ans
    local current_url=""
    
    if [ -z "${NC_HOST:-}" ]; then
        if [ -z "${NONINTERACTIVE:-}" ]; then
            read -p "[your Nextcloud's hostname/prefix] " ans
        fi
        [ -z "$ans" ] && return 0
    else
        current_url="$NC_PROTO://$NC_HOST:$NC_PORT$NC_PREFIX"
        if [ -z "${NONINTERACTIVE:-}" ]; then
            read -p "[$current_url] " ans
            if [ -z "$ans" ]; then
                ans="$current_url"
            
            elif [ "$ans" == "none" ]; then
                ans=""
            fi
        else
            ans="$current_url"
        fi
    fi

    case "$ans" in
        https://* )
            NC_PROTO="https"
            NC_PORT="443"
            ans="$(awk -F: '{print substr($0,9)}' <<< "$ans")"
            ;;
        http://* )
            NC_PROTO="http"
            NC_PORT="80"
            ans="$(awk -F: '{print substr($0,8)}' <<< "$ans")"
            ;;
        * )
            NC_PROTO="https"
            NC_PORT="443"
            ;;
    esac
    
    NC_PREFIX="/$(awk -F/ '{print substr($0,length($1)+2)}' <<< "$ans")"
    NC_HOST="$(awk -F/ '{print $1}' <<< "$ans")"
    
    if grep ":" <<< "$NC_HOST" >/dev/null; then
        NC_PORT="$(awk -F: '{print $2}'  <<< "$NC_HOST")"
        NC_HOST="$(awk -F: '{print $1}' <<< "$NC_HOST")"
    fi
    
    local new_url="$NC_PROTO://$NC_HOST:$NC_PORT$NC_PREFIX"

    if [ ! -z "$NC_HOST" ]; then
        echo "Using Nextcloud ${new_url}"

        # configure roundcube contacts
        configure_roundcube "$NC_HOST"
        
        # configure zpush (which links to contacts & calendar)
        configure_zpush
        
        # prevent nginx from serving any miab-installed nextcloud
        # files and remove owncloud cron job
        chmod 000 /usr/local/lib/owncloud
        rm -f /etc/cron.d/mailinabox-nextcloud
    fi
    
    tools/editconf.py /etc/mailinabox_mods.conf \
                      "NC_PROTO=$NC_PROTO" \
                      "NC_HOST=$NC_HOST" \
                      "NC_PORT=$NC_PORT" \
                      "NC_PREFIX=$NC_PREFIX"
}

remote_nextcloud_handler
