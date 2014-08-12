# Owncloud
##########################

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

apt_install \
	dbconfig-common \
	php5-cli php5-sqlite php5-gd php5-imap php5-curl php-pear php-apc curl libapr1 libtool libcurl4-openssl-dev php-xml-parser \
	php5 php5-dev php5-gd php5-fpm memcached php5-memcache unzip sqlite

apt-get purge -qq -y owncloud*

# Install ownCloud from source if it is not already present
# TODO: Check version?
if [ ! -d /usr/local/lib/owncloud ]; then
	echo Installing ownCloud...
	rm -f /tmp/owncloud.zip
	wget -qO /tmp/owncloud.zip https://download.owncloud.org/community/owncloud-7.0.1.zip
	unzip /tmp/owncloud.zip -d /usr/local/lib
	rm -f /tmp/owncloud.zip
fi

# Create a configuration file.
TIMEZONE=`cat /etc/timezone`
if [ ! -f "/usr/local/lib/owncloud/config/config.php" ]; then
    cat - > /usr/local/lib/owncloud/config/config.php <<EOF;
<?php

\$CONFIG = array (
  'datadirectory' => '$STORAGE_ROOT/owncloud',
  'user_backends' => array(
    array(
      'class'=>'OC_User_IMAP',
      'arguments'=>array('{localhost:993/imap/ssl/novalidate-cert}')
    )
  ),
  "memcached_servers" => array (
    array('localhost', 11211),
  ),
  'mail_smtpmode' => 'sendmail',
  'mail_smtpsecure' => '',
  'mail_smtpauthtype' => 'LOGIN',
  'mail_smtpauth' => false,
  'mail_smtphost' => '',
  'mail_smtpport' => '',
  'mail_smtpname' => '',
  'mail_smtppassword' => '',
  'mail_from_address' => 'owncloud',
  'mail_domain' => '$PRIMARY_HOSTNAME',
  'logtimezone' => '$TIMEZONE',
);
?>
EOF
fi

# Set permissions
mkdir -p $STORAGE_ROOT/owncloud
chown -R www-data.www-data $STORAGE_ROOT/owncloud /usr/local/lib/owncloud

# Download and install the mail app
# TODO: enable mail app in ownCloud config, not exposed afaik?
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
chmod -R 777 /usr/local/lib/owncloud/apps/mail/vendor/ezyang/htmlpurifier/library/HTMLPurifier/DefinitionCache/Serializer

# Use Crontab instead of AJAX/webcron in ownCloud
# TODO: somehow change the cron option in ownClouds config, not exposed afaik?
(crontab -u www-user -l; echo "*/15  *  *  *  * php -f /usr/local/lib/owncloud/cron.php" ) | crontab -u www-user -

php5enmod imap
restart_service php5-fpm
