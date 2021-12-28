#!/bin/bash
# Nextcloud
##########################

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# ### Installing Nextcloud

echo "Installing Nextcloud (contacts/calendar)..."

apt-get purge -qq -y owncloud* # we used to use the package manager

apt_install php php-fpm \
	php-cli php-sqlite3 php-gd php-imap php-curl php-pear curl \
	php-dev php-gd php-xml php-mbstring php-zip php-apcu php-json \
	php-intl php-imagick php-gmp php-bcmath

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

	# Empty the skeleton dir to save some space for each new user
	rm -rf /usr/local/lib/owncloud/core/skeleton/*

	# The two apps we actually want are not in Nextcloud core. Download the releases from
	# their github repositories.
	mkdir -p /usr/local/lib/owncloud/apps

	wget_verify https://github.com/nextcloud/contacts/releases/download/v$version_contacts/contacts.tar.gz $hash_contacts /tmp/contacts.tgz
	tar xf /tmp/contacts.tgz -C /usr/local/lib/owncloud/apps/
	rm /tmp/contacts.tgz

	wget_verify https://github.com/nextcloud/calendar/releases/download/v$version_calendar/calendar.tar.gz $hash_calendar /tmp/calendar.tgz
	tar xf /tmp/calendar.tgz -C /usr/local/lib/owncloud/apps/
	rm /tmp/calendar.tgz

	# Starting with Nextcloud 15, the app user_external is no longer included in Nextcloud core,
	# we will install from their github repository.
	if [ -n "$version_user_external" ]; then
		wget_verify https://github.com/nextcloud/user_external/releases/download/v$version_user_external/user_external-$version_user_external.tar.gz $hash_user_external /tmp/user_external.tgz
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
		sudo -u www-data php /usr/local/lib/owncloud/occ upgrade
		if [ \( $? -ne 0 \) -a \( $? -ne 3 \) ]; then
			echo "Trying ownCloud upgrade again to work around ownCloud upgrade bug..."
			sudo -u www-data php /usr/local/lib/owncloud/occ upgrade
			if [ \( $? -ne 0 \) -a \( $? -ne 3 \) ]; then exit 1; fi
			sudo -u www-data php /usr/local/lib/owncloud/occ maintenance:mode --off
			echo "...which seemed to work."
		fi

		# Add missing indices. NextCloud didn't include this in the normal upgrade because it might take some time.
		sudo -u www-data php /usr/local/lib/owncloud/occ db:add-missing-indices

		# Run conversion to BigInt identifiers, this process may take some time on large tables.
		sudo -u www-data php /usr/local/lib/owncloud/occ db:convert-filecache-bigint --no-interaction
	fi
}

# Nextcloud Version to install. Checks are done down below to step through intermediate versions.
nextcloud_ver=22.2.3
nextcloud_hash=58d2d897ba22a057aa03d29c762c5306211fefd2
contacts_ver=4.0.0
contacts_hash=f893ca57a543b260c9feeecbb5958c00b6998e18
calendar_ver=2.2.2
calendar_hash=923846d48afb5004a456b9079cf4b46d23b3ef3a
user_external_ver=1.0.0
user_external_hash=3bf2609061d7214e7f0f69dd8883e55c4ec8f50a

# Current Nextcloud Version, #1623
# Checking /usr/local/lib/owncloud/version.php shows version of the Nextcloud application, not the DB
# $STORAGE_ROOT/owncloud is kept together even during a backup.  It is better to rely on config.php than
# version.php since the restore procedure can leave the system in a state where you have a newer Nextcloud
# application version than the database.

# If config.php exists, get version number, otherwise CURRENT_NEXTCLOUD_VER is empty.
if [ -f "$STORAGE_ROOT/owncloud/config.php" ]; then
	CURRENT_NEXTCLOUD_VER=$(php -r "include(\"$STORAGE_ROOT/owncloud/config.php\"); echo(\$CONFIG['version']);")
else
	CURRENT_NEXTCLOUD_VER=""
fi

# If the Nextcloud directory is missing (never been installed before, or the nextcloud version to be installed is different
# from the version currently installed, do the install/upgrade
if [ ! -d /usr/local/lib/owncloud/ ] || [[ ! ${CURRENT_NEXTCLOUD_VER} =~ ^$nextcloud_ver ]]; then

	# Stop php-fpm if running. If theyre not running (which happens on a previously failed install), dont bail.
	service php$(php_version)-fpm stop &> /dev/null || /bin/true

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
		elif [[ ${CURRENT_NEXTCLOUD_VER} =~ ^13 ]]; then
			# If we are running Nextcloud 13, upgrade to Nextcloud 14
			InstallNextcloud 14.0.6 4e43a57340f04c2da306c8eea98e30040399ae5a 3.3.0 e55d0357c6785d3b1f3b5f21780cb6d41d32443a 2.0.3 9d9717b29337613b72c74e9914c69b74b346c466
			CURRENT_NEXTCLOUD_VER="14.0.6"
		fi
		if [[ ${CURRENT_NEXTCLOUD_VER} =~ ^14 ]]; then
			# During the upgrade from Nextcloud 14 to 15, user_external may cause the upgrade to fail.
			# We will disable it here before the upgrade and install it again after the upgrade.
			hide_output sudo -u www-data php /usr/local/lib/owncloud/console.php app:disable user_external
			InstallNextcloud 15.0.8 4129d8d4021c435f2e86876225fb7f15adf764a3 3.3.0 e55d0357c6785d3b1f3b5f21780cb6d41d32443a 2.0.3 9d9717b29337613b72c74e9914c69b74b346c466 0.7.0 555a94811daaf5bdd336c5e48a78aa8567b86437
			CURRENT_NEXTCLOUD_VER="15.0.8"
		fi
		if [[ ${CURRENT_NEXTCLOUD_VER} =~ ^15 ]]; then
			InstallNextcloud 16.0.6 0bb3098455ec89f5af77a652aad553ad40a88819 3.3.0 e55d0357c6785d3b1f3b5f21780cb6d41d32443a 2.0.3 9d9717b29337613b72c74e9914c69b74b346c466 0.7.0 555a94811daaf5bdd336c5e48a78aa8567b86437
			CURRENT_NEXTCLOUD_VER="16.0.6"
		fi
        if [[ ${CURRENT_NEXTCLOUD_VER} =~ ^16 ]]; then
			InstallNextcloud 17.0.6 50b98d2c2f18510b9530e558ced9ab51eb4f11b0 3.3.0 e55d0357c6785d3b1f3b5f21780cb6d41d32443a 2.0.3 9d9717b29337613b72c74e9914c69b74b346c466 0.7.0 555a94811daaf5bdd336c5e48a78aa8567b86437
			CURRENT_NEXTCLOUD_VER="17.0.6"
        fi
        if [[ ${CURRENT_NEXTCLOUD_VER} =~ ^17 ]]; then
        	# Don't exit the install if this column already exists (see #2076)
			(echo "ALTER TABLE oc_flow_operations ADD COLUMN entity VARCHAR;" | sqlite3 $STORAGE_ROOT/owncloud/owncloud.db 2>/dev/null) || true
            InstallNextcloud 18.0.10 39c0021a8b8477c3f1733fddefacfa5ebf921c68 3.4.1 aee680a75e95f26d9285efd3c1e25cf7f3bfd27e 2.0.3 9d9717b29337613b72c74e9914c69b74b346c466 1.0.0 3bf2609061d7214e7f0f69dd8883e55c4ec8f50a
            CURRENT_NEXTCLOUD_VER="18.0.10"
	    fi
		if [[ ${CURRENT_NEXTCLOUD_VER} =~ ^18 ]]; then
			InstallNextcloud 19.0.4 01e98791ba12f4860d3d4047b9803f97a1b55c60 3.4.1 aee680a75e95f26d9285efd3c1e25cf7f3bfd27e 2.0.3 9d9717b29337613b72c74e9914c69b74b346c466 1.0.0 3bf2609061d7214e7f0f69dd8883e55c4ec8f50a
			CURRENT_NEXTCLOUD_VER="19.0.4"
		fi
		if [[ ${CURRENT_NEXTCLOUD_VER} =~ ^19 ]]; then
			InstallNextcloud 20.0.14 92cac708915f51ee2afc1787fd845476fd090c81 4.0.0 f893ca57a543b260c9feeecbb5958c00b6998e18 2.2.2 923846d48afb5004a456b9079cf4b46d23b3ef3a 1.0.0 3bf2609061d7214e7f0f69dd8883e55c4ec8f50a
			CURRENT_NEXTCLOUD_VER="20.0.14"
			
			# Nextcloud 20 needs to have some optional columns added
			sudo -u www-data php /usr/local/lib/owncloud/occ db:add-missing-columns
		fi
		if [[ ${CURRENT_NEXTCLOUD_VER} =~ ^20 ]]; then
			InstallNextcloud 21.0.7 f5c7079c5b56ce1e301c6a27c0d975d608bb01c9 4.0.0 f893ca57a543b260c9feeecbb5958c00b6998e18 2.2.2 923846d48afb5004a456b9079cf4b46d23b3ef3a 1.0.0 3bf2609061d7214e7f0f69dd8883e55c4ec8f50a
			CURRENT_NEXTCLOUD_VER="21.0.7"
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
      'class' => 'OC_User_IMAP',
        'arguments' => array(
          '127.0.0.1', 143, null
         ),
    ),
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

\$CONFIG['user_backends'] = array(array('class' => 'OC_User_IMAP','arguments' => array('127.0.0.1', 143, null),),);

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
hide_output sudo -u www-data php /usr/local/lib/owncloud/console.php app:disable firstrunwizard
hide_output sudo -u www-data php /usr/local/lib/owncloud/console.php app:enable user_external
hide_output sudo -u www-data php /usr/local/lib/owncloud/console.php app:enable contacts
hide_output sudo -u www-data php /usr/local/lib/owncloud/console.php app:enable calendar

# When upgrading, run the upgrade script again now that apps are enabled. It seems like
# the first upgrade at the top won't work because apps may be disabled during upgrade?
# Check for success (0=ok, 3=no upgrade needed).
sudo -u www-data php /usr/local/lib/owncloud/occ upgrade
if [ \( $? -ne 0 \) -a \( $? -ne 3 \) ]; then exit 1; fi

# Disable default apps that we don't support
sudo -u www-data \
	php /usr/local/lib/owncloud/occ app:disable photos dashboard activity \
	| (grep -v "No such app enabled" || /bin/true)

# Install interesting apps
installed=$(sudo -u www-data php /usr/local/lib/owncloud/occ app:list | grep 'notes')

if [ -z "$installed" ]; then
    sudo -u www-data php /usr/local/lib/owncloud/occ app:install notes
fi

hide_output sudo -u www-data php /usr/local/lib/owncloud/console.php app:enable notes

installed=$(sudo -u www-data php /usr/local/lib/owncloud/occ app:list | grep 'twofactor_totp')

if [ -z "$installed" ]; then
	sudo -u www-data php /usr/local/lib/owncloud/occ app:install twofactor_totp
fi

hide_output sudo -u www-data php /usr/local/lib/owncloud/console.php app:enable twofactor_totp

# upgrade apps
sudo -u www-data php /usr/local/lib/owncloud/occ app:update --all

# Set PHP FPM values to support large file uploads
# (semicolon is the comment character in this file, hashes produce deprecation warnings)
tools/editconf.py /etc/php/$(php_version)/fpm/php.ini -c ';' \
	upload_max_filesize=16G \
	post_max_size=16G \
	output_buffering=16384 \
	memory_limit=512M \
	max_execution_time=600 \
	short_open_tag=On

# Set Nextcloud recommended opcache settings
tools/editconf.py /etc/php/$(php_version)/cli/conf.d/10-opcache.ini -c ';' \
	opcache.enable=1 \
	opcache.enable_cli=1 \
	opcache.interned_strings_buffer=8 \
	opcache.max_accelerated_files=10000 \
	opcache.memory_consumption=128 \
	opcache.save_comments=1 \
	opcache.revalidate_freq=1

# Set up a cron job for Nextcloud.
cat > /etc/cron.d/mailinabox-nextcloud << EOF;
#!/bin/bash
# Mail-in-a-Box
*/5 * * * *	root	sudo -u www-data php -f /usr/local/lib/owncloud/cron.php
EOF
chmod +x /etc/cron.d/mailinabox-nextcloud

# Remove previous hourly cronjob
rm -f /etc/cron.hourly/mailinabox-owncloud

# There's nothing much of interest that a user could do as an admin for Nextcloud,
# and there's a lot they could mess up, so we don't make any users admins of Nextcloud.
# But if we wanted to, we would do this:
# ```
# for user in $(management/cli.py user admins); do
#	 sqlite3 $STORAGE_ROOT/owncloud/owncloud.db "INSERT OR IGNORE INTO oc_group_user VALUES ('admin', '$user')"
# done
# ```

# Enable PHP modules and restart PHP.
restart_service php$(php_version)-fpm
