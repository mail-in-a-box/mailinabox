#!/bin/bash
# CardDAV client/sync for RoundCube Mail
##########################

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars
RCMPLUGINDIR=/usr/local/lib/roundcubemail/plugins/
CARDDAVDIR=${RCMPLUGINDIR}/carddav/
CARDDAVCONF=${CARDDAVDIR}/config.inc.php
CARDDAVGIT=https://github.com/blind-coder/rcmcarddav.git
RCMCONFIG=/usr/local/lib/roundcubemail/config/config.inc.php
CURRDIR=`pwd`
# ### Clone
git_clone $CARDDAVGIT master '' $CARDDAVDIR

# ### Install composer

# We need php5-curl for this
apt_install php5-curl

# This doesn't like hide_output so we keep things quiet the old fashioned way
COMPOSERLOG=/tmp/rcmcarddav-composer-install.log
cd $CARDDAVDIR
curl -sS https://getcomposer.org/installer 2> $COMPOSERLOG | php 2>&1 >> $COMPOSERLOG
php composer.phar install 2>> $COMPOSERLOG | php 2>&1 >> $COMPOSERLOG
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
