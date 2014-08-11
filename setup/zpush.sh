#!/bin/bash
#
# Z-Push: The Microsoft Exchange protocol server.
# Mostly for use on iOS which doesn't support IMAP.
#
# Although Ubuntu ships Z-Push (as d-push) it has a dependency on Apache
# so we won't install it that way.
#
# Thanks to http://frontender.ch/publikationen/push-mail-server-using-nginx-and-z-push.html.

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# Prereqs.

apt_install \
	php-soap php5-imap

php5enmod imap

# Copy Z-Push into place.
if [ ! -d /usr/local/lib/z-push ]; then
	rm -f /tmp/zpush.zip
	wget -qO /tmp/zpush.zip https://github.com/fmbiete/Z-Push-contrib/archive/master.zip
	unzip /tmp/zpush.zip -d /usr/local/lib/
	mv /usr/local/lib/Z-Push-contrib-master /usr/local/lib/z-push
	ln -s /usr/local/lib/z-push/z-push-admin.php /usr/sbin/z-push-admin
	ln -s /usr/local/lib/z-push/z-push-top.php /usr/sbin/z-push-top
	rm /tmp/zpush.zip;
fi

# Configure default config
# TODO: Add timezone etc?
sed -i "s/define('BACKEND_PROVIDER', .*/define('BACKEND_PROVIDER', 'BackendCombined');/" /usr/local/lib/z-push/config.php

# Configure BACKEND
rm -f /usr/local/lib/z-push/backend/combined/config.php
cp conf/zpush_backend_combined.php /usr/local/lib/z-push/backend/combined/config.php

# Configure IMAP. Tell is to connect to email via IMAP using SSL. Since we connect on
# localhost, the certificate won't match (it may be self-signed and invalid anyway)
# so don't check the cert.
sed -i "s/define('IMAP_SERVER', .*/define('IMAP_SERVER', 'localhost');/" /usr/local/lib/z-push/backend/imap/config.php
sed -i "s/define('IMAP_PORT', .*/define('IMAP_PORT', 993);/" /usr/local/lib/z-push/backend/imap/config.php
sed -i "s/define('IMAP_OPTIONS', .*/define('IMAP_OPTIONS', '\/ssl\/norsh\/novalidate-cert');/" /usr/local/lib/z-push/backend/imap/config.php

# Configure CardDav
sed -i "s/define('CARDDAV_PROTOCOL', .*/define('CARDDAV_PROTOCOL', 'https');/" /usr/local/lib/z-push/backend/carddav/config.php
sed -i "s/define('CARDDAV_SERVER', .*/define('CARDDAV_SERVER', 'localhost');/" /usr/local/lib/z-push/backend/carddav/config.php
sed -i "s/define('CARDDAV_PORT', .*/define('CARDDAV_PORT', '443');/" /usr/local/lib/z-push/backend/carddav/config.php
sed -i "s/define('CARDDAV_PATH', .*/define('CARDDAV_PATH', '/remote.php/carddav/addressbooks/%u/');/" /usr/local/lib/z-push/backend/carddav/config.php

# Configure CalDav
sed -i "s/define('CALDAV_SERVER', .*/define('CALDAV_SERVER', 'https://localhost');/" /usr/local/lib/z-push/backend/caldav/config.php
sed -i "s/define('CALDAV_PORT', .*/define('CALDAV_PORT', '443');/" /usr/local/lib/z-push/backend/caldav/config.php
sed -i "s/define('CALDAV_PATH', .*/define('CALDAV_PATH', '/remote.php/caldav/calendars/%u/');/" /usr/local/lib/z-push/backend/caldav/config.php

# Some directories it will use.

mkdir -p /var/log/z-push
mkdir -p /var/lib/z-push
chmod 750 /var/log/z-push
chmod 750 /var/lib/z-push
chown www-data:www-data /var/log/z-push
chown www-data:www-data /var/lib/z-push

# Restart service.

restart_service php-fastcgi
