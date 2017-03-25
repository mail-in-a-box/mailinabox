#!/bin/bash
# Owncloud
##########################

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# ### Installing ownCloud

echo "Installing ownCloud (contacts/calendar)..."

apt_install \
	dbconfig-common \
	php5-cli php5-sqlite php5-gd php5-imap php5-curl php-pear php-apc curl libapr1 libtool libcurl4-openssl-dev php-xml-parser \
	php5 php5-dev php5-gd php5-fpm memcached php5-memcached

apt-get purge -qq -y owncloud*

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

InstallOwncloud() {

	version=$1
	hash=$2

	echo
	echo "Upgrading to ownCloud version $version"
	echo

	# Remove the current owncloud
	rm -rf /usr/local/lib/owncloud

	# Download and verify
	wget_verify https://download.owncloud.org/community/owncloud-$version.zip $hash /tmp/owncloud.zip

	# Extract ownCloud
	unzip -q /tmp/owncloud.zip -d /usr/local/lib
	rm -f /tmp/owncloud.zip

	# The two apps we actually want are not in ownCloud core. Download the releases from
	# their github repositories.
	mkdir -p /usr/local/lib/owncloud/apps
	wget_verify https://github.com/owncloud/contacts/releases/download/v1.4.0.0/contacts.tar.gz c1c22d29699456a45db447281682e8bc3f10e3e7 /tmp/contacts.tgz
	tar xf /tmp/contacts.tgz -C /usr/local/lib/owncloud/apps/
	rm /tmp/contacts.tgz

        wget_verify https://github.com/nextcloud/calendar/releases/download/v1.4.0/calendar.tar.gz c84f3170efca2a99ea6254de34b0af3cb0b3a821 /tmp/calendar.tgz
	tar xf /tmp/calendar.tgz -C /usr/local/lib/owncloud/apps/
	rm /tmp/calendar.tgz

	# Fix weird permissions.
	chmod 750 /usr/local/lib/owncloud/{apps,config}

	# Create a symlink to the config.php in STORAGE_ROOT (for upgrades we're restoring the symlink we previously
	# put in, and in new installs we're creating a symlink and will create the actual config later).
	ln -sf $STORAGE_ROOT/owncloud/config.php /usr/local/lib/owncloud/config/config.php

	# Make sure permissions are correct or the upgrade step won't run.
	# $STORAGE_ROOT/owncloud may not yet exist, so use -f to suppress
	# that error.
	chown -f -R www-data.www-data $STORAGE_ROOT/owncloud /usr/local/lib/owncloud

	# If this isn't a new installation, immediately run the upgrade script.
	# Then check for success (0=ok and 3=no upgrade needed, both are success).
	if [ -e $STORAGE_ROOT/owncloud/owncloud.db ]; then
		# ownCloud 8.1.1 broke upgrades. It may fail on the first attempt, but
		# that can be OK.
		sudo -u www-data php /usr/local/lib/owncloud/occ upgrade
		if [ \( $? -ne 0 \) -a \( $? -ne 3 \) ]; then
			echo "Trying ownCloud upgrade again to work around ownCloud upgrade bug..."
			sudo -u www-data php /usr/local/lib/owncloud/occ upgrade
			if [ \( $? -ne 0 \) -a \( $? -ne 3 \) ]; then exit 1; fi
			sudo -u www-data php /usr/local/lib/owncloud/occ maintenance:mode --off
			echo "...which seemed to work."
		fi
	fi
}

owncloud_ver=9.1.2

# Check if ownCloud dir exist, and check if version matches owncloud_ver (if either doesn't - install/upgrade)
if [ ! -d /usr/local/lib/owncloud/ ] \
        || ! grep -q $owncloud_ver /usr/local/lib/owncloud/version.php; then

	# Stop php-fpm
	hide_output service php5-fpm stop

        # Backup the existing ownCloud.
	# Create a backup directory to store the current installation and database to
	BACKUP_DIRECTORY=$STORAGE_ROOT/owncloud-backup/`date +"%Y-%m-%d-%T"`
	mkdir -p "$BACKUP_DIRECTORY"
	if [ -d /usr/local/lib/owncloud/ ]; then
		echo "upgrading ownCloud to $owncloud_ver (backing up existing ownCloud installation, configuration and database to directory to $BACKUP_DIRECTORY..."
		cp -r /usr/local/lib/owncloud "$BACKUP_DIRECTORY/owncloud-install"
	fi
	if [ -e /home/user-data/owncloud/owncloud.db ]; then
		cp /home/user-data/owncloud/owncloud.db $BACKUP_DIRECTORY
        fi
        if [ -e /home/user-data/owncloud/config.php ]; then
                cp /home/user-data/owncloud/config.php $BACKUP_DIRECTORY
        fi

	# We only need to check if we do upgrades when owncloud was previously installed
	if [ -e /usr/local/lib/owncloud/version.php ]; then
		if grep -q "8\.1\.[0-9]" /usr/local/lib/owncloud/version.php; then
			echo "We are running 8.1.x, upgrading to 8.2.3 first"
			InstallOwncloud 8.2.3 bfdf6166fbf6fc5438dc358600e7239d1c970613
		fi

		# If we are upgrading from 8.2.x we should go to 9.0 first. Owncloud doesn't support skipping minor versions
		if grep -q "8\.2\.[0-9]" /usr/local/lib/owncloud/version.php; then
			echo "We are running version 8.2.x, upgrading to 9.0.2 first"

			# We need to disable memcached. The upgrade and install fails
			# with memcached
			CONFIG_TEMP=$(/bin/mktemp)
			php <<EOF > $CONFIG_TEMP && mv $CONFIG_TEMP $STORAGE_ROOT/owncloud/config.php;
			<?php
				include("$STORAGE_ROOT/owncloud/config.php");

				\$CONFIG['memcache.local'] = '\OC\Memcache\APC';

				echo "<?php\n\\\$CONFIG = ";
				var_export(\$CONFIG);
				echo ";";
			?>
EOF
			chown www-data.www-data $STORAGE_ROOT/owncloud/config.php

			# We can now install owncloud 9.0.2
			InstallOwncloud 9.0.2 72a3d15d09f58c06fa8bee48b9e60c9cd356f9c5

			# The owncloud 9 migration doesn't migrate calendars and contacts
			# The option to migrate these are removed in 9.1
			# So the migrations should be done when we have 9.0 installed
			sudo -u www-data php /usr/local/lib/owncloud/occ dav:migrate-addressbooks
			# The following migration has to be done for each owncloud user
			for directory in $STORAGE_ROOT/owncloud/*@*/ ; do
				username=$(basename "${directory}")
				sudo -u www-data php /usr/local/lib/owncloud/occ dav:migrate-calendar $username
			done
			sudo -u www-data php /usr/local/lib/owncloud/occ dav:sync-birthday-calendar
		fi
	fi

	InstallOwncloud $owncloud_ver ba9b1cdb681b8a3607d928cbe56f52e3888d9296
fi

# ### Configuring ownCloud

# Setup ownCloud if the ownCloud database does not yet exist. Running setup when
# the database does exist wipes the database and user data.
if [ ! -f $STORAGE_ROOT/owncloud/owncloud.db ]; then
	# Create user data directory
	mkdir -p $STORAGE_ROOT/owncloud

	# Create an initial configuration file.
	instanceid=oc$(echo $PRIMARY_HOSTNAME | sha1sum | fold -w 10 | head -n 1)
	cat > $STORAGE_ROOT/owncloud/config.php <<EOF;
<?php
\$CONFIG = array (
  'datadirectory' => '$STORAGE_ROOT/owncloud',

  'instanceid' => '$instanceid',

  'forcessl' => true, # if unset/false, ownCloud sends a HSTS=0 header, which conflicts with nginx config

  'overwritewebroot' => '/cloud',
  'overwrite.cli.url' => '/cloud',
  'user_backends' => array(
    array(
      'class'=>'OC_User_IMAP',
      'arguments'=>array('{127.0.0.1:993/imap/ssl/novalidate-cert}')
    )
  ),
  'memcache.local' => '\OC\Memcache\APC',
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
);
?>
EOF

	# Create an auto-configuration file to fill in database settings
	# when the install script is run. Make an administrator account
	# here or else the install can't finish.
	adminpassword=$(dd if=/dev/urandom bs=1 count=40 2>/dev/null | sha1sum | fold -w 30 | head -n 1)
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

# Update config.php.
# * trusted_domains is reset to localhost by autoconfig starting with ownCloud 8.1.1,
#   so set it here. It also can change if the box's PRIMARY_HOSTNAME changes, so
#   this will make sure it has the right value.
# * Some settings weren't included in previous versions of Mail-in-a-Box.
# * We need to set the timezone to the system timezone to allow fail2ban to ban
#   users within the proper timeframe
# * We need to set the logdateformat to something that will work correctly with fail2ban
# Use PHP to read the settings file, modify it, and write out the new settings array.
TIMEZONE=$(cat /etc/timezone)
CONFIG_TEMP=$(/bin/mktemp)
php <<EOF > $CONFIG_TEMP && mv $CONFIG_TEMP $STORAGE_ROOT/owncloud/config.php;
<?php
include("$STORAGE_ROOT/owncloud/config.php");

\$CONFIG['trusted_domains'] = array('$PRIMARY_HOSTNAME');

\$CONFIG['memcache.local'] = '\OC\Memcache\APC';
\$CONFIG['overwrite.cli.url'] = '/cloud';
\$CONFIG['mail_from_address'] = 'administrator'; # just the local part, matches our master administrator address

\$CONFIG['logtimezone'] = '$TIMEZONE';
\$CONFIG['logdateformat'] = 'Y-m-d H:i:s';

echo "<?php\n\\\$CONFIG = ";
var_export(\$CONFIG);
echo ";";
?>
EOF
chown www-data.www-data $STORAGE_ROOT/owncloud/config.php

# Enable/disable apps. Note that this must be done after the ownCloud setup.
# The firstrunwizard gave Josh all sorts of problems, so disabling that.
# user_external is what allows ownCloud to use IMAP for login. The contacts
# and calendar apps are the extensions we really care about here.
hide_output sudo -u www-data php /usr/local/lib/owncloud/console.php app:disable firstrunwizard
hide_output sudo -u www-data php /usr/local/lib/owncloud/console.php app:enable user_external
hide_output sudo -u www-data php /usr/local/lib/owncloud/console.php app:enable contacts
hide_output sudo -u www-data php /usr/local/lib/owncloud/console.php app:enable calendar

# When upgrading, run the upgrade script again now that apps are enabled. It seems like
# the first upgrade at the top won't work because apps may be disabled during upgrade?
# Check for success (0=ok, 3=no upgrade needed).
sudo -u www-data php /usr/local/lib/owncloud/occ upgrade
if [ \( $? -ne 0 \) -a \( $? -ne 3 \) ]; then exit 1; fi

# Set PHP FPM values to support large file uploads
# (semicolon is the comment character in this file, hashes produce deprecation warnings)
tools/editconf.py /etc/php5/fpm/php.ini -c ';' \
	upload_max_filesize=16G \
	post_max_size=16G \
	output_buffering=16384 \
	memory_limit=512M \
	max_execution_time=600 \
	short_open_tag=On

# If apc is explicitly disabled we need to enable it
if grep -q apc.enabled=0 /etc/php5/mods-available/apcu.ini; then
	tools/editconf.py /etc/php5/mods-available/apcu.ini -c ';' \
		apc.enabled=1
fi

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
