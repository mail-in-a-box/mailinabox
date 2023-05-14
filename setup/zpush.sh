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
# Z-Push: The Microsoft Exchange protocol server
# ----------------------------------------------
#
# Mostly for use on iOS which doesn't support IMAP IDLE.
#
# Although Ubuntu ships Z-Push (as d-push) it has a dependency on Apache
# so we won't install it that way.
#
# Thanks to http://frontender.ch/publikationen/push-mail-server-using-nginx-and-z-push.html.

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# Prereqs.

echo "Installing Z-Push (Exchange/ActiveSync server)..."
apt_install \
       php${PHP_VER}-soap php${PHP_VER}-imap libawl-php php$PHP_VER-xml

phpenmod -v $PHP_VER imap

# Copy Z-Push into place.
VERSION=2.7.0
TARGETHASH=a520bbdc1d637c5aac379611053457edd54f2bf0
needs_update=0 #NODOC
if [ ! -f /usr/local/lib/z-push/version ]; then
	needs_update=1 #NODOC
elif [[ $VERSION != $(cat /usr/local/lib/z-push/version) ]]; then
	# checks if the version
	needs_update=1 #NODOC
fi
if [ $needs_update == 1 ]; then
	# Download
	wget_verify "https://github.com/Z-Hub/Z-Push/archive/refs/tags/$VERSION.zip" $TARGETHASH /tmp/z-push.zip

	# Extract into place.
	rm -rf /usr/local/lib/z-push /tmp/z-push
	unzip -q /tmp/z-push.zip -d /tmp/z-push
	mv /tmp/z-push/*/src /usr/local/lib/z-push
	rm -rf /tmp/z-push.zip /tmp/z-push

	rm -f /usr/sbin/z-push-{admin,top}
	echo $VERSION > /usr/local/lib/z-push/version
fi

# Configure default config.
sed -i "s^define('TIMEZONE', .*^define('TIMEZONE', '$(cat /etc/timezone)');^" /usr/local/lib/z-push/config.php
sed -i "s/define('BACKEND_PROVIDER', .*/define('BACKEND_PROVIDER', 'BackendCombined');/" /usr/local/lib/z-push/config.php
sed -i "s/define('USE_FULLEMAIL_FOR_LOGIN', .*/define('USE_FULLEMAIL_FOR_LOGIN', true);/" /usr/local/lib/z-push/config.php
sed -i "s/define('LOG_MEMORY_PROFILER', .*/define('LOG_MEMORY_PROFILER', false);/" /usr/local/lib/z-push/config.php
sed -i "s/define('BUG68532FIXED', .*/define('BUG68532FIXED', false);/" /usr/local/lib/z-push/config.php
sed -i "s/define('LOGLEVEL', .*/define('LOGLEVEL', LOGLEVEL_ERROR);/" /usr/local/lib/z-push/config.php

# Configure BACKEND
rm -f /usr/local/lib/z-push/backend/combined/config.php
cp conf/zpush/backend_combined.php /usr/local/lib/z-push/backend/combined/config.php

# Configure IMAP
rm -f /usr/local/lib/z-push/backend/imap/config.php
cp conf/zpush/backend_imap.php /usr/local/lib/z-push/backend/imap/config.php
sed -i "s%STORAGE_ROOT%$STORAGE_ROOT%" /usr/local/lib/z-push/backend/imap/config.php

# Configure CardDav
rm -f /usr/local/lib/z-push/backend/carddav/config.php
cp conf/zpush/backend_carddav.php /usr/local/lib/z-push/backend/carddav/config.php

# Configure CalDav
rm -f /usr/local/lib/z-push/backend/caldav/config.php
cp conf/zpush/backend_caldav.php /usr/local/lib/z-push/backend/caldav/config.php

# Configure Autodiscover
rm -f /usr/local/lib/z-push/autodiscover/config.php
cp conf/zpush/autodiscover_config.php /usr/local/lib/z-push/autodiscover/config.php
sed -i "s/PRIMARY_HOSTNAME/$PRIMARY_HOSTNAME/" /usr/local/lib/z-push/autodiscover/config.php
sed -i "s^define('TIMEZONE', .*^define('TIMEZONE', '$(cat /etc/timezone)');^" /usr/local/lib/z-push/autodiscover/config.php
sed -i "s/define('LOGAUTHFAIL', .*/define('LOGAUTHFAIL', true);/" /usr/local/lib/z-push/config.php

# Some directories it will use.

mkdir -p /var/log/z-push
mkdir -p /var/lib/z-push
chmod 750 /var/log/z-push
chmod 750 /var/lib/z-push
chown www-data:www-data /var/log/z-push
chown www-data:www-data /var/lib/z-push

# Add log rotation

cat > /etc/logrotate.d/z-push <<EOF;
/var/log/z-push/*.log {
	weekly
	missingok
	rotate 52
	compress
	delaycompress
	notifempty
}
EOF

# Restart service.

restart_service php$PHP_VER-fpm

# Fix states after upgrade

hide_output php$PHP_VER /usr/local/lib/z-push/z-push-admin.php -a fixstates
