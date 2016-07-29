#!/bin/bash
# Webmail with Rainloop
# ----------------------

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# ### Installing Rainloop

# Rainloop's webpage (http://www.rainloop.net/downloads/) does not easily	#
# list versions as the need for VERSION_FILENAME below. 			#

# 
# Dependancies are from Roundcube, not all may be needed for Rainloop		#

echo "Installing Rainloop (webmail)..."
apt_install \
	unzip \
	php5 php5-mcrypt php5-cli php5-curl php5-sqlite php-net-sieve php5-common \
	crudini
apt_get_quiet remove php-mail-mimedecode # no longer needed since Roundcube 1.1.3

# We used to install Roundcube from Ubuntu, without triggering the dependencies #NODOC
# on Apache and MySQL, by downloading the debs and installing them manually. #NODOC
# Now that we're beyond that, get rid of those debs before installing from source. #NODOC
apt-get purge -qq -y roundcube* #NODOC

# Install Roundcube from source if it is not already present or if it is out of date.
# Combine the Roundcube version number with the commit hash of vacation_sieve to track
# whether we have the latest version.
VERSION=v1.10.2.145
VERSION_FILENAME="rainloop-community-1.10.2.145-74dc686dd82d9f29b0fef8ceb11c2903.zip"
HASH=ee1b9cd4c2494aaecf7d291500aee9b455bbee58
UPDATE_KEY=$VERSION
needs_update=0 #NODOC
first_install=0
if [ ! -f /usr/local/lib/rainloop/version ]; then
	# not installed yet #NODOC
	needs_update=1 #NODOC
	first_install=1
elif [[ "$UPDATE_KEY" != "$(cat /usr/local/lib/rainloop/version)" ]]; then
	# checks if the version is what we want
	needs_update=1 #NODOC
fi
if [ $needs_update == 1 ]; then
	# install rainloop
	wget_verify \
		https://github.com/RainLoop/rainloop-webmail/releases/download/$VERSION/$VERSION_FILENAME \
		$HASH \
		/tmp/rainloop.zip
	# Per documentation, updates can overwrite existing files
	unzip -q -o /tmp/rainloop.zip -d /usr/local/lib/rainloop
	rm -f /tmp/rainloop.zip


	# record the version we've installed
	echo $UPDATE_KEY > /usr/local/lib/rainloop/version
fi

# ### Configuring Rainloop

# Create a configuration file.
#

# Some application paths are not created until the application is launched
# this should include the internal process it has when upgrading between versions

# Fix permissions
find /usr/local/lib/rainloop -type d -exec chmod 755 {} \;
find /usr/local/lib/rainloop -type f -exec chmod 644 {} \;
chown -R www-data:www-data /usr/local/lib/rainloop

# Fixing permissions needs to happen first or else curl gets
# this error: [105] Missing version directory

/usr/bin/php /usr/local/lib/rainloop/index.php > /dev/null


if [ $first_install == 1 ]; then

# Set customized configuration
# Rainloop has a default password set, not sure yet how to integrate with userlist
# for now we should change it from the default
# Methods for changing password: https://github.com/RainLoop/rainloop-webmail/issues/28
#
#	Using the Rainloop API:
random_admin_pw=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)

echo "<?php

\$_ENV['RAINLOOP_INCLUDE_AS_API'] = true;
include '/usr/local/lib/rainloop/index.php';

\$oConfig = \RainLoop\Api::Config();
\$oConfig->SetPassword('$random_admin_pw');
echo \$oConfig->Save() ? 'Done' : 'Error';

?>" | /usr/bin/php


crudini --set --existing /usr/local/lib/rainloop/data/_data_/_default_/configs/application.ini \
	contacts enable On
crudini --set --existing /usr/local/lib/rainloop/data/_data_/_default_/configs/application.ini \
	contacts allow_sync On
crudini --set --existing /usr/local/lib/rainloop/data/_data_/_default_/configs/application.ini \
	login determine_user_domain On
crudini --set --existing /usr/local/lib/rainloop/data/_data_/_default_/configs/application.ini \
        login default_domain $PRIMARY_HOSTNAME

# Disable google imap login in Rainloop
echo -n ",gmail.com" >> /usr/local/lib/rainloop/data/_data_/_default_/domains/disabled

# Add localhost imap/smtp

cat > /usr/local/lib/rainloop/data/_data_/_default_/domains/default.ini <<EOF;
imap_host = "127.0.0.1"
imap_port = 993
imap_secure = "SSL"
imap_short_login = Off
sieve_use = On
sieve_allow_raw = Off
sieve_host = "127.0.0.1"
sieve_port = 4190
sieve_secure = "None"
smtp_host = "127.0.0.1"
smtp_port = 587
smtp_secure = "TLS"
smtp_short_login = Off
smtp_auth = On
smtp_php_mail = Off
EOF


# Fix permissions after editing configs

find /usr/local/lib/rainloop -type d -exec chmod 755 {} \;
find /usr/local/lib/rainloop -type f -exec chmod 644 {} \;
chown -R www-data:www-data /usr/local/lib/rainloop

fi

# Enable PHP modules.
php5enmod mcrypt
restart_service php5-fpm

# remove Roundcube
rm -rf /usr/local/lib/roundcube
