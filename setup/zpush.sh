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
	php-soap php5-imap libawl-php php5-xsl

php5enmod imap

# Copy Z-Push into place.
if [ ! -d /usr/local/lib/z-push ]; then
	rm -f /tmp/zpush.zip
	echo installing z-push...
	wget -qO /tmp/zpush.zip https://github.com/fmbiete/Z-Push-contrib/archive/master.zip
	unzip /tmp/zpush.zip -d /usr/local/lib/
	mv /usr/local/lib/Z-Push-contrib-master /usr/local/lib/z-push
	ln -s /usr/local/lib/z-push/z-push-admin.php /usr/sbin/z-push-admin
	ln -s /usr/local/lib/z-push/z-push-top.php /usr/sbin/z-push-top
	rm /tmp/zpush.zip;
fi

# Configure default config
TIMEZONE=`cat /etc/timezone`
sed -i "s/define('TIMEZONE', .*/define('TIMEZONE', '\$TIMEZONE');/" /usr/local/lib/z-push/config.php
sed -i "s/define('BACKEND_PROVIDER', .*/define('BACKEND_PROVIDER', 'BackendCombined');/" /usr/local/lib/z-push/config.php

# Configure BACKEND
rm -f /usr/local/lib/z-push/backend/combined/config.php
cp conf/zpush/backend_combined.php /usr/local/lib/z-push/backend/combined/config.php

# Configure IMAP
rm -f /usr/local/lib/z-push/backend/imap/config.php
cp conf/zpush/backend_imap.php /usr/local/lib/z-push/backend/imap/config.php

# Configure CardDav
rm -f /usr/local/lib/z-push/backend/carddav/config.php
cp conf/zpush/backend_carddav.php /usr/local/lib/z-push/backend/carddav/config.php

# Configure CalDav
rm -f /usr/local/lib/z-push/backend/caldav/config.php
cp conf/zpush/backend_caldav.php /usr/local/lib/z-push/backend/caldav/config.php

# Some directories it will use.

mkdir -p /var/log/z-push
mkdir -p /var/lib/z-push
chmod 750 /var/log/z-push
chmod 750 /var/lib/z-push
chown www-data:www-data /var/log/z-push
chown www-data:www-data /var/lib/z-push

# Restart service.

restart_service php5-fpm
