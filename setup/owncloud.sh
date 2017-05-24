#!/bin/bash
# Nextcloud
##########################

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# ### Installing Nextcloud

echo "Installing Nextcloud (contacts/calendar)..."

apt_install \
	dbconfig-common \
	php5-cli php5-sqlite php5-gd php5-imap php5-curl php-pear php-apc curl libapr1 libtool libcurl4-openssl-dev php-xml-parser \
	php5 php5-dev php5-gd php5-fpm memcached php5-memcached

apt-get purge -qq -y owncloud*

# Install php-7 from the ppa of the ubuntu php maintainer Ondřej Surý located here https://launchpad.net/%7Eondrej/+archive/ubuntu/php
hide_output add-apt-repository -y ppa:ondrej/php
apt_add_repository_to_unattended_upgrades LP-PPA-ondrej-php:trusty
hide_output apt-get update
apt_install php7.0 php7.0-fpm \
	php7.0-cli php7.0-sqlite php7.0-gd php7.0-imap php7.0-curl php-pear php-apc curl \
        php7.0-dev php7.0-gd memcached php7.0-memcached php7.0-xml php7.0-mbstring php7.0-zip php7.0-apcu

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

InstallNextCloud() {

	version=$1
	hash=$2

	echo
	echo "Upgrading to NextCloud version $version"
	echo

	# Remove the current owncloud/Nextcloud
	rm -rf /usr/local/lib/owncloud

	# Download and verify
	wget_verify https://download.nextcloud.com/server/releases/nextcloud-$version.zip $hash /tmp/nextcloud.zip

	# Extract ownCloud/Nextcloud
	unzip -q /tmp/nextcloud.zip -d /usr/local/lib
	mv /usr/local/lib/nextcloud /usr/local/lib/owncloud
	rm -f /tmp/nextcloud.zip

	# The two apps we actually want are not in Nextcloud core. Download the releases from
	# their github repositories.
	mkdir -p /usr/local/lib/owncloud/apps

	wget_verify https://github.com/nextcloud/contacts/releases/download/v1.5.3/contacts.tar.gz 78c4d49e73f335084feecd4853bd8234cf32615e /tmp/contacts.tgz
	tar xf /tmp/contacts.tgz -C /usr/local/lib/owncloud/apps/
	rm /tmp/contacts.tgz

	wget_verify https://github.com/nextcloud/calendar/releases/download/v1.5.3/calendar.tar.gz b370352d1f280805cc7128f78af4615f623827f8 /tmp/calendar.tgz
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
		sudo -u www-data php7.0 /usr/local/lib/owncloud/occ upgrade
		if [ \( $? -ne 0 \) -a \( $? -ne 3 \) ]; then
			echo "Trying ownCloud upgrade again to work around ownCloud upgrade bug..."
			sudo -u www-data php7.0 /usr/local/lib/owncloud/occ upgrade
			if [ \( $? -ne 0 \) -a \( $? -ne 3 \) ]; then exit 1; fi
			sudo -u www-data php7.0 /usr/local/lib/owncloud/occ maintenance:mode --off
			echo "...which seemed to work."
		fi
	fi
}

# We only install ownCloud intermediate versions to be able to seemlesly upgrade to NextCloud
InstallOwncloud() {

	version=$1
	hash=$2

	echo
	echo "Upgrading to OwnCloud version $version"
	echo

	# Remove the current owncloud/Nextcloud
	rm -rf /usr/local/lib/owncloud

	# Download and verify
	wget_verify https://download.owncloud.org/community/owncloud-$version.zip $hash /tmp/owncloud.zip


	# Extract ownCloud
	unzip -q /tmp/owncloud.zip -d /usr/local/lib
	rm -f /tmp/owncloud.zip

	# The two apps we actually want are not in Nextcloud core. Download the releases from
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

owncloud_ver=12.0.0
owncloud_hash=5d64307d9ce513a8905514b2fbe212f563fe76df

# Check if Nextcloud dir exist, and check if version matches owncloud_ver (if either doesn't - install/upgrade)
if [ ! -d /usr/local/lib/owncloud/ ] \
        || ! grep -q $owncloud_ver /usr/local/lib/owncloud/version.php; then

	# Stop php-fpm
	hide_output service php7.0-fpm stop
	hide_output service php5-fpm stop

	# Backup the existing ownCloud/Nextcloud.
	# Create a backup directory to store the current installation and database to
	BACKUP_DIRECTORY=$STORAGE_ROOT/owncloud-backup/`date +"%Y-%m-%d-%T"`
	mkdir -p "$BACKUP_DIRECTORY"
	if [ -d /usr/local/lib/owncloud/ ]; then
		echo "upgrading ownCloud/Nextcloud to $owncloud_flavor $owncloud_ver (backing up existing installation, configuration and database to directory to $BACKUP_DIRECTORY..."
		cp -r /usr/local/lib/owncloud "$BACKUP_DIRECTORY/owncloud-install"
	fi
	if [ -e /home/user-data/owncloud/owncloud.db ]; then
		cp /home/user-data/owncloud/owncloud.db $BACKUP_DIRECTORY
        fi
        if [ -e /home/user-data/owncloud/config.php ]; then
                cp /home/user-data/owncloud/config.php $BACKUP_DIRECTORY
        fi

	# We only need to check if we do upgrades when owncloud/Nextcloud was previously installed
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

				\$CONFIG['memcache.local'] = '\OC\Memcache\APCu';

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

		# If we are upgrading from 9.0.x we should go to 9.1 first.
		if grep -q "9\.0\.[0-9]" /usr/local/lib/owncloud/version.php; then
			echo "We are running ownCloud 9.0.x, upgrading to ownCloud 9.1.4 first"
			InstallOwncloud 9.1.4 e637cab7b2ca3346164f3506b1a0eb812b4e841a
		fi

		# If we are upgrading from 9.1.x we should go to NextCloud 10.0 first.
		if grep -q "9\.1\.[0-9]" /usr/local/lib/owncloud/version.php; then
			echo "We are running ownCloud 9.0.x, upgrading to NextCloud 10.0.5 first"
			InstallNextCloud 10.0.5 686f6a8e9d7867c32e3bf3ca63b3cc2020564bf6
		fi

		# If we are upgrading from 10.0.x we should go to NextCloud 11.0 first.
		if grep -q "10\.0\.[0-9]" /usr/local/lib/owncloud/version.php; then
			echo "We are running ownCloud 10.0.x, upgrading to NextCloud 11.0.3 first"
			InstallNextCloud 11.0.3 a396aaa1c9f920099a90a86b4a9cd0ec13083c99
		fi
	fi

	InstallNextCloud $owncloud_ver $owncloud_hash
fi

# ### Configuring Nextcloud

# Setup Nextcloud if the Nextcloud database does not yet exist. Running setup when
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

  'forcessl' => true, # if unset/false, Nextcloud sends a HSTS=0 header, which conflicts with nginx config

  'overwritewebroot' => '/cloud',
  'overwrite.cli.url' => '/cloud',
  'user_backends' => array(
    array(
      'class'=>'OC_User_IMAP',
      'arguments'=>array('{127.0.0.1:993/imap/ssl/novalidate-cert}')
    )
  ),
  'memcache.local' => '\OC\Memcache\APCu',
  'mail_smtpmode' => 'sendmail',
  'mail_smtpsecure' => '',
  'mail_smtpauthtype' => 'LOGIN',
  'mail_smtpauth' => false,
  'mail_smtphost' => '',
  'mail_smtpport' => '',
  'mail_smtpname' => '',
  'mail_smtppassword' => '',
  'mail_from_address' => 'owncloud',
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
  # the user does not have to enter anything on first load of Nextcloud
  'adminlogin'    => 'root',
  'adminpass'     => '$adminpassword',
);
?>
EOF

	# Set permissions
	chown -R www-data.www-data $STORAGE_ROOT/owncloud /usr/local/lib/owncloud

	# Execute Nextcloud's setup step, which creates the Nextcloud sqlite database.
	# It also wipes it if it exists. And it updates config.php with database
	# settings and deletes the autoconfig.php file.
	(cd /usr/local/lib/owncloud; sudo -u www-data php7.0 /usr/local/lib/owncloud/index.php;)
fi

# Update config.php.
# * trusted_domains is reset to localhost by autoconfig starting with ownCloud 8.1.1,
#   so set it here. It also can change if the box's PRIMARY_HOSTNAME changes, so
#   this will make sure it has the right value.
# * Some settings weren't included in previous versions of Mail-in-a-Box.
# * We need to set the timezone to the system timezone to allow fail2ban to ban
#   users within the proper timeframe
# * We need to set the logdateformat to something that will work correctly with fail2ban
# * mail_domain' needs to be set every time we run the setup. Making sure we are setting 
#   the correct domain name if the domain is being change from the previous setup.
# Use PHP to read the settings file, modify it, and write out the new settings array.
TIMEZONE=$(cat /etc/timezone)
CONFIG_TEMP=$(/bin/mktemp)
php <<EOF > $CONFIG_TEMP && mv $CONFIG_TEMP $STORAGE_ROOT/owncloud/config.php;
<?php
include("$STORAGE_ROOT/owncloud/config.php");

\$CONFIG['trusted_domains'] = array('$PRIMARY_HOSTNAME');

\$CONFIG['memcache.local'] = '\OC\Memcache\APCu';
\$CONFIG['overwrite.cli.url'] = '/cloud';
\$CONFIG['mail_from_address'] = 'administrator'; # just the local part, matches our master administrator address

\$CONFIG['logtimezone'] = '$TIMEZONE';
\$CONFIG['logdateformat'] = 'Y-m-d H:i:s';

\$CONFIG['mail_domain'] = '$PRIMARY_HOSTNAME';

echo "<?php\n\\\$CONFIG = ";
var_export(\$CONFIG);
echo ";";
?>
EOF
chown www-data.www-data $STORAGE_ROOT/owncloud/config.php

# Enable/disable apps. Note that this must be done after the Nextcloud setup.
# The firstrunwizard gave Josh all sorts of problems, so disabling that.
# user_external is what allows Nextcloud to use IMAP for login. The contacts
# and calendar apps are the extensions we really care about here.
hide_output sudo -u www-data php7.0 /usr/local/lib/owncloud/console.php app:disable firstrunwizard
hide_output sudo -u www-data php7.0 /usr/local/lib/owncloud/console.php app:enable user_external
hide_output sudo -u www-data php7.0 /usr/local/lib/owncloud/console.php app:enable contacts
hide_output sudo -u www-data php7.0 /usr/local/lib/owncloud/console.php app:enable calendar

# When upgrading, run the upgrade script again now that apps are enabled. It seems like
# the first upgrade at the top won't work because apps may be disabled during upgrade?
# Check for success (0=ok, 3=no upgrade needed).
sudo -u www-data php7.0 /usr/local/lib/owncloud/occ upgrade
if [ \( $? -ne 0 \) -a \( $? -ne 3 \) ]; then exit 1; fi

# Set PHP FPM values to support large file uploads
# (semicolon is the comment character in this file, hashes produce deprecation warnings)
tools/editconf.py /etc/php/7.0/fpm/php.ini -c ';' \
	upload_max_filesize=16G \
	post_max_size=16G \
	output_buffering=16384 \
	memory_limit=512M \
	max_execution_time=600 \
	short_open_tag=On

# Configure the path environment for php-fpm
tools/editconf.py /etc/php/7.0/fpm/pool.d/www.conf -c ';' \
        env[PATH]=/usr/local/bin:/usr/bin:/bin

# If apc is explicitly disabled we need to enable it
if grep -q apc.enabled=0 /etc/php/7.0/mods-available/apcu.ini; then
	tools/editconf.py /etc/php/7.0/mods-available/apcu.ini -c ';' \
		apc.enabled=1
fi

# Set up a cron job for Nextcloud.
cat > /etc/cron.hourly/mailinabox-owncloud << EOF;
#!/bin/bash
# Mail-in-a-Box
sudo -u www-data php7.0 -f /usr/local/lib/owncloud/cron.php
EOF
chmod +x /etc/cron.hourly/mailinabox-owncloud

# There's nothing much of interest that a user could do as an admin for Nextcloud,
# and there's a lot they could mess up, so we don't make any users admins of Nextcloud.
# But if we wanted to, we would do this:
# ```
# for user in $(tools/mail.py user admins); do
#	 sqlite3 $STORAGE_ROOT/owncloud/owncloud.db "INSERT OR IGNORE INTO oc_group_user VALUES ('admin', '$user')"
# done
# ```

# Enable PHP modules and restart PHP.
restart_service php5-fpm
restart_service php7.0-fpm
