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
	ZPUSH=z-push-2.1.3-1892
	wget -qO /tmp/zpush.tgz http://download.z-push.org/final/2.1/$ZPUSH.tar.gz
	tar -C /tmp -zxf /tmp/zpush.tgz
	mv /tmp/$ZPUSH /usr/local/lib/z-push
	ln -s /usr/local/lib/z-push/z-push-admin.php /usr/sbin/z-push-admin
	ln -s /usr/local/lib/z-push/z-push-top.php /usr/sbin/z-push-top
	rm /tmp/zpush.tgz;
fi

# Configure. Tell is to connect to email via IMAP using SSL. Since we connect on
# localhost, the certificate won't match (it may be self-signed and invalid anyway)
# so don't check the cert.
sed -i "s/define('BACKEND_PROVIDER', .*/define('BACKEND_PROVIDER', 'BackendIMAP');/" /usr/local/lib/z-push/config.php
#sed -i "s/define('IMAP_SERVER', .*/define('IMAP_SERVER', '$PRIMARY_HOSTNAME');/" /usr/local/lib/z-push/backend/imap/config.php
sed -i "s/define('IMAP_PORT', .*/define('IMAP_PORT', 993);/" /usr/local/lib/z-push/backend/imap/config.php
sed -i "s/define('IMAP_OPTIONS', .*/define('IMAP_OPTIONS', '\/ssl\/norsh\/novalidate-cert');/" /usr/local/lib/z-push/backend/imap/config.php


# Some directories it will use.

mkdir -p /var/log/z-push
mkdir -p /var/lib/z-push
chmod 750 /var/log/z-push
chmod 750 /var/lib/z-push
chown www-data:www-data /var/log/z-push
chown www-data:www-data /var/lib/z-push

# Restart service.

restart_service php-fastcgi
