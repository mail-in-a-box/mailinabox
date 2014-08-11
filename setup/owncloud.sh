# Owncloud
##########################

# TODO: Write documentation on what we're doing here :-)

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

apt_install \
	dbconfig-common \
	php5-cli php5-sqlite php5-gd php5-curl php-pear php-apc curl libapr1 libtool libcurl4-openssl-dev php-xml-parser \
	php5 php5-dev php5-gd php5-fpm memcached php5-memcache unzip

apt-get purge -qq -y owncloud*

# Install ownCloud from source if it is not already present
# TODO: Check version?
if [ ! -d /usr/local/lib/owncloud ]; then
	rm -f /tmp/owncloud.zip
	wget -qO /tmp/owncloud.zip https://download.owncloud.org/community/owncloud-7.0.1.zip
	unzip /tmp/owncloud.zip -d /usr/local/lib
	rm -f /tmp/owncloud.zip
fi

# Create a configuration file.
cat - > /usr/local/lib/owncloud/config/config.php <<EOF;
<?php
/*
 * Do not edit. Written by Mail-in-a-Box. Regenerated on updates.
 */
\$CONFIG = array (
\  'datadirectory' => '$STORAGE_ROOT/owncloud',
\  array (
\    0 =>
\    array (
\    'class' => 'OC_User_IMAP',
\    'arguments' =>
\    array (
\      0 => '{localhost:993/imap/ssl/novalidate-cert}',
\    ),
\  ),
\ ),
\);
EOF

# Insert the following above (owncloud config generation) when we found a good solution:
#  'mail_smtpmode' => 'smtp',
#  'mail_smtpsecure' => 'ssl',
#  'mail_from_address' => '**** need to figure this one out, nornamly: <user>@<domain>.<tld> ****',
#  'mail_domain' => '**** need to figure this one out, nornamly: <domain>.<tld> ****',
#  'mail_smtpauthtype' => 'LOGIN',
#  'mail_smtpauth' => true,
#  'mail_smtphost' => 'localhost',
#  'mail_smtpport' => '587',
#  'mail_smtpname' => '**** need to figure this one out, nornamly: <user>@<domain>.<tld> ****',
#  'mail_smtppassword' => '**** need to figure this one out ****',

# Set permissions
mkdir -p $STORAGE_ROOT/owncloud
chown -R www-data.www-data $STORAGE_ROOT/owncloud /usr/local/lib/owncloud

# Download and install the mail app
if [ ! -d /usr/local/lib/owncloud/apps/mail ]; then
	rm -f /tmp/owncloud_mail.zip
	wget -qO /tmp/owncloud_mail.zip https://github.com/owncloud/mail/archive/master.zip
	unzip /tmp/owncloud_mail.zip -d /usr/local/lib/owncloud/apps
	mv /usr/local/lib/owncloud/apps/mail-master /usr/local/lib/owncloud/apps/mail
	rm -f /tmp/owncloud.zip
fi

# Currently the mail app dosnt ship with the dependencies, so we need to install them
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/lib/owncloud/apps/mail
php /usr/local/lib/owncloud/apps/mail/composer.phar install --working-dir=/usr/local/lib/owncloud/apps/mail

# TODO: enable mail app in ownCloud config?
