#!/bin/bash
# Nextcloud
##########################

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# ### Installing Nextcloud

echo "Installing Nextcloud (contacts/calendar)..."

# Nextcloud core and app (plugin) versions to install.
# With each version we store a hash to ensure we install what we expect.

# Nextcloud core
# --------------
# * See https://nextcloud.com/changelog for the latest version.
# * Check https://docs.nextcloud.com/server/latest/admin_manual/installation/system_requirements.html
#   for whether it supports the version of PHP available on this machine.
# * Since Nextcloud only supports upgrades from consecutive major versions,
#   we automatically install intermediate versions as needed.
# * The hash is the SHA1 hash of the ZIP package, which you can find by just running this script and
#   copying it from the error message when it doesn't match what is below.
nextcloud_ver=24.0.5
nextcloud_hash=a1ecc0db61584ed5fb6f7cf80a492b2fae17ba26

# Nextcloud apps
# --------------
# * Find the most recent tag that is compatible with the Nextcloud version above by
#   consulting the <dependencies>...<nextcloud> node at:
#   https://github.com/nextcloud-releases/contacts/blob/master/appinfo/info.xml
#   https://github.com/nextcloud-releases/calendar/blob/master/appinfo/info.xml
#   https://github.com/nextcloud/user_external/blob/master/appinfo/info.xml
# * The hash is the SHA1 hash of the ZIP package, which you can find by just running this script and
#   copying it from the error message when it doesn't match what is below.
contacts_ver=4.1.0
contacts_hash=697f6b4a664e928d72414ea2731cb2c9d1dc3077
calendar_ver=3.2.2
calendar_hash=ce4030ab57f523f33d5396c6a81396d440756f5f
user_external_ver=3.0.0
user_external_hash=0df781b261f55bbde73d8c92da3f99397000972f

# Clear prior packages and install dependencies from apt.

apt-get purge -qq -y owncloud* # we used to use the package manager

apt_install curl php${PHP_VER} php${PHP_VER}-fpm \
	php${PHP_VER}-cli php${PHP_VER}-sqlite3 php${PHP_VER}-gd php${PHP_VER}-imap php${PHP_VER}-curl \
	php${PHP_VER}-dev php${PHP_VER}-gd php${PHP_VER}-xml php${PHP_VER}-mbstring php${PHP_VER}-zip php${PHP_VER}-apcu \
	php${PHP_VER}-intl php${PHP_VER}-imagick php${PHP_VER}-gmp php${PHP_VER}-bcmath libmagickcore-6.q16-6-extra

# Enable APC before Nextcloud tools are run.
tools/editconf.py /etc/php/$PHP_VER/mods-available/apcu.ini -c ';' \
	apc.enabled=1 \
	apc.enable_cli=1

InstallNextcloud() {

	version=$1
	hash=$2
	version_contacts=$3
	hash_contacts=$4
	version_calendar=$5
	hash_calendar=$6
	version_user_external=${7:-}
	hash_user_external=${8:-}

	echo
	echo "Upgrading to Nextcloud version $version"
	echo

        # Download and verify
        wget_verify https://download.nextcloud.com/server/releases/nextcloud-$version.zip $hash /tmp/nextcloud.zip

	# Remove the current owncloud/Nextcloud
	rm -rf /usr/local/lib/owncloud

	# Extract ownCloud/Nextcloud
	unzip -q /tmp/nextcloud.zip -d /usr/local/lib
	mv /usr/local/lib/nextcloud /usr/local/lib/owncloud
	rm -f /tmp/nextcloud.zip

	# The two apps we actually want are not in Nextcloud core. Download the releases from
	# their github repositories.
	mkdir -p /usr/local/lib/owncloud/apps

	wget_verify https://github.com/nextcloud-releases/contacts/archive/refs/tags/v$version_contacts.tar.gz $hash_contacts /tmp/contacts.tgz
	tar xf /tmp/contacts.tgz -C /usr/local/lib/owncloud/apps/
	rm /tmp/contacts.tgz

	wget_verify https://github.com/nextcloud-releases/calendar/archive/refs/tags/v$version_calendar.tar.gz $hash_calendar /tmp/calendar.tgz
	tar xf /tmp/calendar.tgz -C /usr/local/lib/owncloud/apps/
	rm /tmp/calendar.tgz

	# Starting with Nextcloud 15, the app user_external is no longer included in Nextcloud core,
	# we will install from their github repository.
	if [ -n "$version_user_external" ]; then
		wget_verify https://github.com/nextcloud-releases/user_external/releases/download/v$version_user_external/user_external-v$version_user_external.tar.gz $hash_user_external /tmp/user_external.tgz
		tar -xf /tmp/user_external.tgz -C /usr/local/lib/owncloud/apps/
		rm /tmp/user_external.tgz
	fi

	# Fix weird permissions.
	chmod 750 /usr/local/lib/owncloud/{apps,config}

	# Create a symlink to the config.php in STORAGE_ROOT (for upgrades we're restoring the symlink we previously
	# put in, and in new installs we're creating a symlink and will create the actual config later).
	ln -sf $STORAGE_ROOT/owncloud/config.php /usr/local/lib/owncloud/config/config.php

	# Make sure permissions are correct or the upgrade step won't run.
	# $STORAGE_ROOT/owncloud may not yet exist, so use -f to suppress
	# that error.
	chown -f -R www-data.www-data $STORAGE_ROOT/owncloud /usr/local/lib/owncloud || /bin/true

	# If this isn't a new installation, immediately run the upgrade script.
	# Then check for success (0=ok and 3=no upgrade needed, both are success).
	if [ -e $STORAGE_ROOT/owncloud/owncloud.db ]; then
		# ownCloud 8.1.1 broke upgrades. It may fail on the first attempt, but
		# that can be OK.
		sudo -u www-data php$PHP_VER /usr/local/lib/owncloud/occ upgrade
		if [ \( $? -ne 0 \) -a \( $? -ne 3 \) ]; then
			echo "Trying ownCloud upgrade again to work around ownCloud upgrade bug..."
			sudo -u www-data php$PHP_VER /usr/local/lib/owncloud/occ upgrade
			if [ \( $? -ne 0 \) -a \( $? -ne 3 \) ]; then exit 1; fi
			sudo -u www-data php$PHP_VER /usr/local/lib/owncloud/occ maintenance:mode --off
			echo "...which seemed to work."
		fi

		# Add missing indices. NextCloud didn't include this in the normal upgrade because it might take some time.
		sudo -u www-data php$PHP_VER /usr/local/lib/owncloud/occ db:add-missing-indices

		# Run conversion to BigInt identifiers, this process may take some time on large tables.
		sudo -u www-data php$PHP_VER /usr/local/lib/owncloud/occ db:convert-filecache-bigint --no-interaction
	fi
}

# Current Nextcloud Version, #1623
# Checking /usr/local/lib/owncloud/version.php shows version of the Nextcloud application, not the DB
# $STORAGE_ROOT/owncloud is kept together even during a backup.  It is better to rely on config.php than
# version.php since the restore procedure can leave the system in a state where you have a newer Nextcloud
# application version than the database.

# If config.php exists, get version number, otherwise CURRENT_NEXTCLOUD_VER is empty.
if [ -f "$STORAGE_ROOT/owncloud/config.php" ]; then
	CURRENT_NEXTCLOUD_VER=$(php$PHP_VER -r "include(\"$STORAGE_ROOT/owncloud/config.php\"); echo(\$CONFIG['version']);")
else
	CURRENT_NEXTCLOUD_VER=""
fi

# If the Nextcloud directory is missing (never been installed before, or the nextcloud version to be installed is different
# from the version currently installed, do the install/upgrade
if [ ! -d /usr/local/lib/owncloud/ ] || [[ ! ${CURRENT_NEXTCLOUD_VER} =~ ^$nextcloud_ver ]]; then

	# Stop php-fpm if running. If they are not running (which happens on a previously failed install), dont bail.
	service php$PHP_VER-fpm stop &> /dev/null || /bin/true

	# Backup the existing ownCloud/Nextcloud.
	# Create a backup directory to store the current installation and database to
	BACKUP_DIRECTORY=$STORAGE_ROOT/owncloud-backup/$(date +"%Y-%m-%d-%T")
	mkdir -p "$BACKUP_DIRECTORY"
	if [ -d /usr/local/lib/owncloud/ ]; then
		echo "Upgrading Nextcloud --- backing up existing installation, configuration, and database to directory to $BACKUP_DIRECTORY..."
		cp -r /usr/local/lib/owncloud "$BACKUP_DIRECTORY/owncloud-install"
	fi
	if [ -e $STORAGE_ROOT/owncloud/owncloud.db ]; then
		cp $STORAGE_ROOT/owncloud/owncloud.db $BACKUP_DIRECTORY
	fi
	if [ -e $STORAGE_ROOT/owncloud/config.php ]; then
		cp $STORAGE_ROOT/owncloud/config.php $BACKUP_DIRECTORY
	fi

	# If ownCloud or Nextcloud was previously installed....
	if [ ! -z ${CURRENT_NEXTCLOUD_VER} ]; then
		# Database migrations from ownCloud are no longer possible because ownCloud cannot be run under
		# PHP 7.
		if [[ ${CURRENT_NEXTCLOUD_VER} =~ ^[89] ]]; then
			echo "Upgrades from Mail-in-a-Box prior to v0.28 (dated July 30, 2018) with Nextcloud < 13.0.6 (you have ownCloud 8 or 9) are not supported. Upgrade to Mail-in-a-Box version v0.30 first. Setup will continue, but skip the Nextcloud migration."
			return 0
		elif [[ ${CURRENT_NEXTCLOUD_VER} =~ ^1[012] ]]; then
			echo "Upgrades from Mail-in-a-Box prior to v0.28 (dated July 30, 2018) with Nextcloud < 13.0.6 (you have ownCloud 10, 11 or 12) are not supported. Upgrade to Mail-in-a-Box version v0.30 first. Setup will continue, but skip the Nextcloud migration."
			return 0
		elif [[ ${CURRENT_NEXTCLOUD_VER} =~ ^1[3456789] ]]; then
			echo "Upgrades from Mail-in-a-Box prior to v60 with Nextcloud 19 or earlier are not supported. Upgrade to the latest Mail-in-a-Box version supported on your machine first. Setup will continue, but skip the Nextcloud migration."
			return 0
		fi
		if [[ ${CURRENT_NEXTCLOUD_VER} =~ ^20 ]]; then
			InstallNextcloud 21.0.7 f5c7079c5b56ce1e301c6a27c0d975d608bb01c9 4.0.7 45e7cf4bfe99cd8d03625cf9e5a1bb2e90549136 3.0.4 d0284b68135777ec9ca713c307216165b294d0fe
			CURRENT_NEXTCLOUD_VER="21.0.7"
		fi
		if [[ ${CURRENT_NEXTCLOUD_VER} =~ ^21 ]]; then
			InstallNextcloud 22.2.6 9d39741f051a8da42ff7df46ceef2653a1dc70d9 4.1.0 697f6b4a664e928d72414ea2731cb2c9d1dc3077 3.2.2 ce4030ab57f523f33d5396c6a81396d440756f5f 3.0.0 0df781b261f55bbde73d8c92da3f99397000972f
			CURRENT_NEXTCLOUD_VER="22.2.6"
		fi

		# Remove the read-onlyness of the config.
		sed -ie '/config_is_read_only/d' $STORAGE_ROOT/owncloud/config.php

		if [[ ${CURRENT_NEXTCLOUD_VER} =~ ^22 ]]; then
			InstallNextcloud 23.0.9 b6ac7ffa6c1c1c6187fea7d9efc7a32300cdc377 4.1.0 697f6b4a664e928d72414ea2731cb2c9d1dc3077 3.2.2 ce4030ab57f523f33d5396c6a81396d440756f5f 3.0.0 0df781b261f55bbde73d8c92da3f99397000972f
			CURRENT_NEXTCLOUD_VER="23.0.9"
		fi
	fi

	InstallNextcloud $nextcloud_ver $nextcloud_hash $contacts_ver $contacts_hash $calendar_ver $calendar_hash $user_external_ver $user_external_hash
fi

# ### Configuring Nextcloud

# Setup Nextcloud if the Nextcloud database does not yet exist. Running setup when
# the database does exist wipes the database and user data.
if [ ! -f $STORAGE_ROOT/owncloud/owncloud.db ]; then
	# Create user data directory
	mkdir -p $STORAGE_ROOT/owncloud

	# Create an initial configuration file.
	instanceid=oc$(echo $PRIMARY_HOSTNAME | sha1sum | fold -w 10 | head -n 1)
	CONFIG_TEMP=/tmp/cfg-$instanceid.json
	cat > $CONFIG_TEMP <<EOF
	{
		"system": {
			"datadirectory": "$STORAGE_ROOT/owncloud",
			"instanceid": "$instanceid",
			"forcessl": true,
			"overwritewebroot": "/cloud",
			"overwrite.cli.url": "https://${PRIMARY_HOSTNAME}/cloud",
			"user_backends": [
				{
					"class": "\\\OCA\\\UserExternal\\\IMAP",
					"arguments": [ "127.0.0.1", 143, null, null, false, false ]
				}
			],
		  "memcache.local": "\\\OC\\\Memcache\\\APCu",
		  "mail_smtpmode": "sendmail",
		  "mail_smtpsecure": "",
		  "mail_smtpauthtype": "LOGIN",
		  "mail_smtpauth": false,
		  "mail_smtphost": "",
		  "mail_smtpport": "",
		  "mail_smtpname": "",
		  "mail_smtppassword": "",
		  "mail_from_address": "owncloud"
		}
	}
EOF

	sudo -u www-data php8.0 /usr/local/lib/owncloud/occ config:import $CONFIG_TEMP
	rm -f $CONFIG_TEMP

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
	(cd /usr/local/lib/owncloud; sudo -u www-data php$PHP_VER /usr/local/lib/owncloud/index.php;)
fi

# Enable/disable apps. Note that this must be done after the Nextcloud setup.
# The firstrunwizard gave Josh all sorts of problems, so disabling that.
# user_external is what allows Nextcloud to use IMAP for login. The contacts
# and calendar apps are the extensions we really care about here.
hide_output sudo -u www-data php$PHP_VER /usr/local/lib/owncloud/console.php app:disable firstrunwizard
hide_output sudo -u www-data php$PHP_VER /usr/local/lib/owncloud/console.php app:enable user_external
hide_output sudo -u www-data php$PHP_VER /usr/local/lib/owncloud/console.php app:enable contacts
hide_output sudo -u www-data php$PHP_VER /usr/local/lib/owncloud/console.php app:enable calendar

# When upgrading, run the upgrade script again now that apps are enabled. It seems like
# the first upgrade at the top won't work because apps may be disabled during upgrade?
# Check for success (0=ok, 3=no upgrade needed).
sudo -u www-data php$PHP_VER /usr/local/lib/owncloud/occ upgrade
if [ \( $? -ne 0 \) -a \( $? -ne 3 \) ]; then exit 1; fi

# Disable default apps that we don't support
sudo -u www-data \
	php$PHP_VER /usr/local/lib/owncloud/occ app:disable \
		photos dashboard activity circles federation files_sharing \
		notifications files_pdfviewer password_policy systemtags comments \
		privacy recommendations files_rightclick sharebymail support text \
		theming survey_client user_status weather_status files_videoplayer \
	| (grep -v "No such app enabled" || /bin/true)

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
instanceid=oc$(echo $PRIMARY_HOSTNAME | sha1sum | fold -w 10 | head -n 1)
CONFIG_TEMP=/tmp/cfg-$instanceid.json
PHONE_REGION=$(locale | grep TELEPHONE | sed -e 's/LC_.*=".*_//' | sed -e 's/\..*//')
cat > $CONFIG_TEMP <<-EOF
{
	"system": {
		"config_is_read_only": true,
		"trusted_domains": ["$PRIMARY_HOSTNAME"],
	  "memcache.local": "\\\OC\\\Memcache\\\APCu",
	  "mail_from_address": "administrator",
	  "logtimezone": "$TIMEZONE",
	  "logdateformat": "Y-m-d H:i:s",
	  "mail_domain": "$PRIMARY_HOSTNAME",
	  "default_phone_region": "$PHONE_REGION",
		"user_backends": [
			{
				"class": "\\\OCA\\\UserExternal\\\IMAP",
				"arguments": [ "127.0.0.1", 143, null, null, false, false ]
			}
		]
	}
}
EOF
sudo -u www-data php8.0 /usr/local/lib/owncloud/occ config:import $CONFIG_TEMP
rm -f $CONFIG_TEMP

# Set PHP FPM values to support large file uploads
# (semicolon is the comment character in this file, hashes produce deprecation warnings)
tools/editconf.py /etc/php/$PHP_VER/fpm/php.ini -c ';' \
	upload_max_filesize=16G \
	post_max_size=16G \
	output_buffering=16384 \
	memory_limit=512M \
	max_execution_time=600 \
	short_open_tag=On

# Set Nextcloud recommended opcache settings
tools/editconf.py /etc/php/$PHP_VER/cli/conf.d/10-opcache.ini -c ';' \
	opcache.enable=1 \
	opcache.enable_cli=1 \
	opcache.interned_strings_buffer=8 \
	opcache.max_accelerated_files=10000 \
	opcache.memory_consumption=128 \
	opcache.save_comments=1 \
	opcache.revalidate_freq=1

# Migrate users_external data from <0.6.0 to version 3.0.0 (see https://github.com/nextcloud/user_external).
# This version was probably in use in Mail-in-a-Box v0.41 (February 26, 2019) and earlier.
# We moved to v0.6.3 in 193763f8. Ignore errors - maybe there are duplicated users with the
# correct backend already.
sqlite3 $STORAGE_ROOT/owncloud/owncloud.db "UPDATE oc_users_external SET backend='127.0.0.1';" || /bin/true

# Set up a cron job for Nextcloud.
cat > /etc/cron.d/mailinabox-nextcloud << EOF;
#!/bin/bash
# Mail-in-a-Box
*/5 * * * *	root	sudo -u www-data php$PHP_VER -f /usr/local/lib/owncloud/cron.php
EOF
chmod +x /etc/cron.d/mailinabox-nextcloud

# Rotate the nextcloud.log file
cat > /etc/logrotate.d/nextcloud <<EOF
# Nextcloud logs 
$STORAGE_ROOT/owncloud/nextcloud.log { 
		size 10M
		create 640 www-data www-data
		rotate 30
		copytruncate
		missingok
		compress 
}
EOF

# There's nothing much of interest that a user could do as an admin for Nextcloud,
# and there's a lot they could mess up, so we don't make any users admins of Nextcloud.
# But if we wanted to, we would do this:
# ```
# for user in $(management/cli.py user admins); do
#	 sqlite3 $STORAGE_ROOT/owncloud/owncloud.db "INSERT OR IGNORE INTO oc_group_user VALUES ('admin', '$user')"
# done
# ```

# Enable PHP modules and restart PHP.
restart_service php$PHP_VER-fpm
