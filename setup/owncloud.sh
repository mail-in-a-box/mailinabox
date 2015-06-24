#!/bin/bash
# Owncloud
##########################

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# ### Installing ownCloud

apt_install \
	dbconfig-common \
	php5-cli php5-sqlite php5-gd php5-imap php5-curl php-pear php-apc curl libapr1 libtool libcurl4-openssl-dev php-xml-parser \
	php5 php5-dev php5-gd php5-fpm memcached php5-memcache unzip

apt-get purge -qq -y owncloud*

# Install ownCloud from source of this version:
owncloud_ver=8.0.4
owncloud_hash=625b1c561ea51426047a3e79eda51ca05e9f978a

# Migrate <= v0.10 setups that stored the ownCloud config.php in /usr/local rather than
# in STORAGE_ROOT. Move the file to STORAGE_ROOT.
if [ ! -f $STORAGE_ROOT/owncloud/config.php ] \
	&& [ -f /usr/local/lib/owncloud/config/config.php ]; then

	# Move config.php and symlink back into previous location.
	echo "Migrating owncloud/config.php to new location."
	mv /usr/local/lib/owncloud/config/config.php $STORAGE_ROOT/owncloud/config.php \
		&& \
	ln -sf $STORAGE_ROOT/owncloud/config.php /usr/local/lib/owncloud/config/config.php
fi

# Check if ownCloud dir exist, and check if version matches owncloud_ver (if either doesn't - install/upgrade)
if [ ! -d /usr/local/lib/owncloud/ ] \
	|| ! grep -q $owncloud_ver /usr/local/lib/owncloud/version.php; then

	# Download and verify
	echo "installing ownCloud..."
	wget_verify https://download.owncloud.org/community/owncloud-$owncloud_ver.zip $owncloud_hash /tmp/owncloud.zip

	# Clear out the existing ownCloud.
	if [ -d /usr/local/lib/owncloud/ ]; then
		echo "upgrading ownCloud to $owncloud_ver (backing up existing ownCloud directory to /tmp/owncloud-backup-$$)..."
		mv /usr/local/lib/owncloud /tmp/owncloud-backup-$$
	fi

	# Extract ownCloud
	unzip -u -o -q /tmp/owncloud.zip -d /usr/local/lib #either extracts new or replaces current files
	rm -f /tmp/owncloud.zip

	# The two apps we actually want are not in ownCloud core. Clone them from
	# their github repositories.
	mkdir -p /usr/local/lib/owncloud/apps
	git_clone https://github.com/owncloud/contacts v$owncloud_ver '' /usr/local/lib/owncloud/apps/contacts
	git_clone https://github.com/owncloud/calendar v$owncloud_ver '' /usr/local/lib/owncloud/apps/calendar

	# Fix weird permissions.
	chmod 750 /usr/local/lib/owncloud/{apps,config}

	# Create a symlink to the config.php in STORAGE_ROOT (for upgrades we're restoring the symlink we previously
	# put in, and in new installs we're creating a symlink and will create the actual config later).
	ln -sf $STORAGE_ROOT/owncloud/config.php /usr/local/lib/owncloud/config/config.php

	# Make sure permissions are correct or the upgrade step won't run.
	# $STORAGE_ROOT/owncloud may not yet exist, so use -f to suppress
	# that error.
	chown -f -R www-data.www-data $STORAGE_ROOT/owncloud /usr/local/lib/owncloud

	# Run the upgrade script (if ownCloud is already up-to-date it wont matter).
	hide_output sudo -u www-data php /usr/local/lib/owncloud/occ upgrade
fi

# ### Configuring ownCloud

# Setup ownCloud if the ownCloud database does not yet exist. Running setup when
# the database does exist wipes the database and user data.
if [ ! -f $STORAGE_ROOT/owncloud/owncloud.db ]; then
	# Create user data directory
	mkdir -p $STORAGE_ROOT/owncloud

	# Create a configuration file.
	TIMEZONE=$(cat /etc/timezone)
	instanceid=oc$(echo $PRIMARY_HOSTNAME | sha1sum | fold -w 10 | head -n 1)
	cat > $STORAGE_ROOT/owncloud/config.php <<EOF;
<?php
\$CONFIG = array (
  'datadirectory' => '$STORAGE_ROOT/owncloud',

  'instanceid' => '$instanceid',

  'trusted_domains' =>
    array (
      0 => '$PRIMARY_HOSTNAME',
    ),
  'forcessl' => true, # if unset/false, ownCloud sends a HSTS=0 header, which conflicts with nginx config

  'overwritewebroot' => '/cloud',
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

	# Create an auto-configuration file to fill in database settings
	# when the install script is run. Make an administrator account
	# here or else the install can't finish.
	adminpassword=$(dd if=/dev/random bs=1 count=40 2>/dev/null | sha1sum | fold -w 30 | head -n 1)
	cat > /usr/local/lib/owncloud/config/autoconfig.php <<EOF;
<?php
\$AUTOCONFIG = array (
  # storage/database
  'directory' => '$STORAGE_ROOT/owncloud',
  'dbtype' => 'sqlite3',

  # create an administrator account with a random password so that
  # the user does not have to enter anything on first load of ownCloud
  'adminlogin'    => 'root',
  'adminpass'     => '$adminpassword',
);
?>
EOF

	# Set permissions
	chown -R www-data.www-data $STORAGE_ROOT/owncloud /usr/local/lib/owncloud

	# Execute ownCloud's setup step, which creates the ownCloud sqlite database.
	# It also wipes it if it exists. And it updates config.php with database
	# settings and deletes the autoconfig.php file.
	(cd /usr/local/lib/owncloud; sudo -u www-data php /usr/local/lib/owncloud/index.php;)
fi

# Enable/disable apps. Note that this must be done after the ownCloud setup.
# The firstrunwizard gave Josh all sorts of problems, so disabling that.
# user_external is what allows ownCloud to use IMAP for login. The contacts
# and calendar apps are the extensions we really care about here.
hide_output sudo -u www-data php /usr/local/lib/owncloud/console.php app:disable firstrunwizard
hide_output sudo -u www-data php /usr/local/lib/owncloud/console.php app:enable user_external
hide_output sudo -u www-data php /usr/local/lib/owncloud/console.php app:enable contacts
hide_output sudo -u www-data php /usr/local/lib/owncloud/console.php app:enable calendar

# Set PHP FPM values to support large file uploads
# (semicolon is the comment character in this file, hashes produce deprecation warnings)
tools/editconf.py /etc/php5/fpm/php.ini -c ';' \
	upload_max_filesize=16G \
	post_max_size=16G \
	output_buffering=16384 \
	memory_limit=512M \
	max_execution_time=600 \
	short_open_tag=On

# Set up a cron job for owncloud.
cat > /etc/cron.hourly/mailinabox-owncloud << EOF;
#!/bin/bash
# Mail-in-a-Box
sudo -u www-data php -f /usr/local/lib/owncloud/cron.php
EOF
chmod +x /etc/cron.hourly/mailinabox-owncloud

# There's nothing much of interest that a user could do as an admin for ownCloud,
# and there's a lot they could mess up, so we don't make any users admins of ownCloud.
# But if we wanted to, we would do this:
# ```
# for user in $(tools/mail.py user admins); do
#	 sqlite3 $STORAGE_ROOT/owncloud/owncloud.db "INSERT OR IGNORE INTO oc_group_user VALUES ('admin', '$user')"
# done
# ```

# Enable PHP modules and restart PHP.
php5enmod imap
restart_service php5-fpm
