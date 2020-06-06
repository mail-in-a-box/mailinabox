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
    local nc_host="$1"
    local nc_prefix="$2"
    [ "$nc_prefix" == "/" ] && nc_prefix=""
    
    # Configure CardDav
    if [ ! -z "$nc_host" ]
    then
        cp setup/mods.available/conf/zpush/backend_carddav.php $ZPUSH_DIR/backend/carddav/config.php
        cp setup/mods.available/conf/zpush/backend_caldav.php $ZPUSH_DIR/backend/caldav/config.php
        sed -i "s/127\.0\.0\.1/$nc_host/g" $ZPUSH_DIR/backend/carddav/config.php
        sed -i "s^NC_PREFIX^$nc_prefix^g" $ZPUSH_DIR/backend/carddav/config.php
        sed -i "s/127\.0\.0\.1/$nc_host/g" $ZPUSH_DIR/backend/caldav/config.php
        sed -i "s^NC_PREFIX^$nc_prefix^g" $ZPUSH_DIR/backend/caldav/config.php
    fi
}


configure_roundcube() {
    # replace the plugin configuration from the default Mail-In-A-Box
    local name="$1"
    local nc_host="$2"
    local nc_prefix="$3"
    [ "$nc_prefix" == "/" ] && nc_prefix=""
    
    # Configure CardDav
    cat > ${RCM_PLUGIN_DIR}/carddav/config.inc.php <<EOF
<?php
/* Do not edit. Written by Mail-in-a-Box-LDAP mods. Regenerated on updates. */
\$prefs['_GLOBAL']['hide_preferences'] = true;
\$prefs['_GLOBAL']['suppress_version_warning'] = true;
\$prefs['cloud'] = array(
	 'name'         =>  '$name',
	 'username'     =>  '%u', // login username
	 'password'     =>  '%p', // login password
	 'url'          =>  'https://${nc_host}${nc_prefix}/remote.php/carddav/addressbooks/%u/contacts',
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
    echo "Configure a remote Nextcloud"
    echo "============================"
    echo 'Enter the hostname and web prefix of your remote Nextcloud'
    echo 'For example:'
    echo '    "cloud.mydomain.com/" - Nextcloud server with no prefix'
    echo '    "cloud.mydomain.com"  - same as above'
    echo '    "www.mydomain.com/cloud"  - a Nextcloud server having a prefix /cloud'
    echo ''
    
    local ans_hostname
    local ans_prefix
        
    if [ -z "${NC_HOST:-}" ]; then
        if [ -z "${NONINTERACTIVE:-}" ]; then
            read -p "[your Nextcloud's hostname/prefix] " ans_hostname
        fi
        [ -z "$ans_hostname" ] && return 0
    else
        if [ -z "${NONINTERACTIVE:-}" ]; then
            read -p "[$NC_HOST/$NC_PREFIX] " ans_hostname
            if [ -z "$ans_hostname" ]; then
                ans_hostname="$NC_HOST/$NC_PREFIX"
            
            elif [ "$ans_hostname" == "none" ]; then
                ans_hostname=""
            fi
        else
            ans_hostname="${NC_HOST}${NC_PREFIX}"
        fi
    fi

    ans_prefix="/$(awk -F/ '{print substr($0,length($1)+2)}' <<< "$ans_hostname")"
    ans_hostname="$(awk -F/ '{print $1}' <<< "$ans_hostname")"
    

    if [ ! -z "$ans_hostname" ]; then
        echo "Using Nextcloud ${ans_hostname}${ans_prefix}"

        # configure roundcube contacts
        configure_roundcube "$ans_hostname" "$ans_hostname" "$ans_prefix"
        
        # configure zpush (which links to contacts & calendar)
        configure_zpush "$ans_hostname" "$ans_prefix"
        
        # prevent nginx from serving any miab-installed nextcloud files
        chmod 000 /usr/local/lib/owncloud
    fi
    
    tools/editconf.py /etc/mailinabox_mods.conf \
                      "NC_HOST=$ans_hostname" \
                      "NC_PREFIX=$ans_prefix"
}

remote_nextcloud_handler
