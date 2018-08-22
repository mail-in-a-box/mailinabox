#!/bin/bash
# Nextcloud
##########################

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# ### Installing Nextcloud

echo "Installing Nextcloud (contacts/calendar)..."

# Keep the php5 dependancies for the owncloud upgrades
apt_install \
	dbconfig-common \
	php5-cli php5-sqlite php5-gd php5-imap php5-curl php-pear php-apc curl libapr1 libtool libcurl4-openssl-dev php-xml-parser \
	php5 php5-dev php5-gd php5-fpm memcached php5-memcached

apt-get purge -qq -y owncloud*

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

InstallNextcloud() {

	version=$1
	hash=$2

	echo
	echo "Upgrading to Nextcloud version $version"
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

# We only install ownCloud intermediate versions to be able to seemlesly upgrade to Nextcloud
InstallOwncloud() {

	version=$1
	hash=$2

	echo
	echo "Upgrading to OwnCloud version $version"
	echo

	# Remove the current owncloud/Nextcloud
	rm -rf /usr/local/lib/owncloud

	# Download and verify
	wget_verify https://download.owncloud.org/community/owncloud-$version.tar.bz2 $hash /tmp/owncloud.tar.bz2


	# Extract ownCloud
	tar xjf /tmp/owncloud.tar.bz2 -C /usr/local/lib
	rm -f /tmp/owncloud.tar.bz2

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
		sudo -u www-data php5 /usr/local/lib/owncloud/occ upgrade
		if [ \( $? -ne 0 \) -a \( $? -ne 3 \) ]; then
			echo "Trying ownCloud upgrade again to work around ownCloud upgrade bug..."
			sudo -u www-data php5 /usr/local/lib/owncloud/occ upgrade
			if [ \( $? -ne 0 \) -a \( $? -ne 3 \) ]; then exit 1; fi
			sudo -u www-data php5 /usr/local/lib/owncloud/occ maintenance:mode --off
			echo "...which seemed to work."
		fi
	fi
}

owncloud_ver=12.0.5
owncloud_hash=d25afbac977a4e331f5e38df50aed0844498ca86

# Check if Nextcloud dir exist, and check if version matches owncloud_ver (if either doesn't - install/upgrade)
if [ ! -d /usr/local/lib/owncloud/ ] \
        || ! grep -q $owncloud_ver /usr/local/lib/owncloud/version.php; then

	# Stop php-fpm if running. If theyre not running (which happens on a previously failed install), dont bail.
	service php7.0-fpm stop &> /dev/null || /bin/true
	service php5-fpm stop &> /dev/null || /bin/true

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
		if grep -q "OC_VersionString = '8\.1\.[0-9]" /usr/local/lib/owncloud/version.php; then
			echo "We are running 8.1.x, upgrading to 8.2.11 first"
			InstallOwncloud 8.2.11 e4794938fc2f15a095018ba9d6ee18b53f6f299c
		fi

		# If we are upgrading from 8.2.x we should go to 9.0 first. Owncloud doesn't support skipping minor versions
		if grep -q "OC_VersionString = '8\.2\.[0-9]" /usr/local/lib/owncloud/version.php; then
			echo "We are running version 8.2.x, upgrading to 9.0.11 first"

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

			# We can now install owncloud 9.0.11
			InstallOwncloud 9.0.11 fc8bad8a62179089bc58c406b28997fb0329337b

			# The owncloud 9 migration doesn't migrate calendars and contacts
			# The option to migrate these are removed in 9.1
			# So the migrations should be done when we have 9.0 installed
			sudo -u www-data php5 /usr/local/lib/owncloud/occ dav:migrate-addressbooks
			# The following migration has to be done for each owncloud user
			for directory in $STORAGE_ROOT/owncloud/*@*/ ; do
				username=$(basename "${directory}")
				sudo -u www-data php5 /usr/local/lib/owncloud/occ dav:migrate-calendar $username
			done
			sudo -u www-data php5 /usr/local/lib/owncloud/occ dav:sync-birthday-calendar
		fi

		# If we are upgrading from 9.0.x we should go to 9.1 first.
		if grep -q "OC_VersionString = '9\.0\.[0-9]" /usr/local/lib/owncloud/version.php; then
			echo "We are running ownCloud 9.0.x, upgrading to ownCloud 9.1.7 first"
			InstallOwncloud 9.1.7 1307d997d0b23dc42742d315b3e2f11423a9c808
		fi

		# Newer ownCloud 9.1.x versions cannot be upgraded to Nextcloud 10 and have to be
		# upgraded to Nextcloud 11 straight away, see:
		# https://github.com/nextcloud/server/issues/2203
		# However, for some reason, upgrading to the latest Nextcloud 11.0.7 doesn't
		# work either. Therefore, we're upgrading to Nextcloud 11.0.0 in the interim.
		# This should not be a problem since we're upgrading to the latest Nextcloud 12
		# in the next step.
		if grep -q "OC_VersionString = '9\.1\.[0-9]" /usr/local/lib/owncloud/version.php; then
			echo "We are running ownCloud 9.1.x, upgrading to Nextcloud 11.0.0 first"
			InstallNextcloud 11.0.0 e8c9ebe72a4a76c047080de94743c5c11735e72e
		fi

		# If we are upgrading from 10.0.x we should go to Nextcloud 11.0 first.
		if grep -q "OC_VersionString = '10\.0\.[0-9]" /usr/local/lib/owncloud/version.php; then
			echo "We are running Nextcloud 10.0.x, upgrading to Nextcloud 11.0.7 first"
			InstallNextcloud 11.0.7 f936ddcb2ae3dbb66ee4926eb8b2ebbddc3facbe
		fi
	fi

	InstallNextcloud $owncloud_ver $owncloud_hash
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
# * Automatically add e-mail accounts in nextcloud mail
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

\$CONFIG['app.mail.accounts.default'] = array(
    'email' => '%EMAIL%',
    'imapHost' => '$PRIMARY_HOSTNAME',
    'imapPort' => 993,
    'imapSslMode' => 'ssl',
    'smtpHost' => '$PRIMARY_HOSTNAME',
    'smtpPort' => 587,
    'smtpSslMode' => 'tls',
);

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

# Set PHP FPM values to support large file uploads
# (semicolon is the comment character in this file, hashes produce deprecation warnings)
tools/editconf.py /etc/php/7.0/fpm/php.ini -c ';' \
	upload_max_filesize=16G \
	post_max_size=16G \
	output_buffering=16384 \
	memory_limit=512M \
	max_execution_time=600 \
	short_open_tag=On

# Set Nextcloud recommended opcache settings
tools/editconf.py /etc/php/7.0/cli/conf.d/10-opcache.ini -c ';' \
	opcache.enable=1 \
	opcache.enable_cli=1 \
	opcache.interned_strings_buffer=8 \
	opcache.max_accelerated_files=10000 \
	opcache.memory_consumption=128 \
	opcache.save_comments=1 \
	opcache.revalidate_freq=1

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
sudo -u www-data php -f /usr/local/lib/owncloud/cron.php
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
restart_service php7.0-fpm
