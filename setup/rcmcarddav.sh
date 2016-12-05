#!/bin/bash
# CardDAV client/sync for RoundCube Mail
##########################

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars
RCMPLUGINDIR=/usr/local/lib/roundcubemail/plugins/
CARDDAVDIR=${RCMPLUGINDIR}carddav/
CARDDAVCONF=${CARDDAVDIR}/config.inc.php
CARDDAVTAR=https://github.com/blind-coder/rcmcarddav/releases/download/v2.0.4/carddav-2.0.4.tar.bz2
RCMCONFIG=/usr/local/lib/roundcubemail/config/config.inc.php
CURRDIR=`pwd`
# get the release and extract it in the right place
wget -q $CARDDAVTAR -O /tmp/rcmcarddav.tar.bz2
tar -xjf /tmp/rcmcarddav.tar.bz2 -C $RCMPLUGINDIR
rm /tmp/rcmcarddav.tar.bz2

cd $CURRDIR

# ### Configure rcmcarddav
cat > $CARDDAVCONF <<EOF;
<?php
\$prefs['ownCloud'] = array(
                   // required attributes
                   'name'         =>  'ownCloud',
                   // will be substituted for the roundcube username
                   'username'     =>  '%u',
                   // will be substituted for the roundcube password
                   'password'     =>  '%p',
                   // %u will be substituted for the CardDAV username
                   'url'          =>  'https://${PRIMARY_HOSTNAME}/cloud/remote.php/carddav/addressbooks/%u/contacts',
                   'active'       =>  true,
                   'readonly'     =>  false,
                   'refresh_time' => '02:00:00',
                   'fixed'        =>  array('username','password'),
                   'preemptive_auth' => '1',
                   'hide'        =>  false,
);
EOF

# Enable plugin
sed -ri "s@'vacation_sieve'\)@'vacation_sieve', 'carddav'\)@" $RCMCONFIG

# Fix permissions.
chmod -R 644 $CARDDAVDIR
chmod -R a+X $CARDDAVDIR
chmod -R 644 $RCMCONFIG
chmod -R a+X $RCMCONFIG

# Make sure ownership is correct
chown -f -R www-data.www-data $CARDDAVDIR
chown -f -R www-data.www-data $RCMCONFIG

# Should be all set after a restart
restart_service nginx
