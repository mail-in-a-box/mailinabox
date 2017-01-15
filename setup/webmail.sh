#!/bin/bash
# Webmail with Roundcube
# ----------------------

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# ### Installing Roundcube

# We install Roundcube from sources, rather than from Ubuntu, because:
#
# 1. Ubuntu's `roundcube-core` package has dependencies on Apache & MySQL, which we don't want.
#
# 2. The Roundcube shipped with Ubuntu is consistently out of date.
#
# 3. It's packaged incorrectly --- it seems to be missing a directory of files.
#
# So we'll use apt-get to manually install the dependencies of roundcube that we know we need,
# and then we'll manually install roundcube from source.

# These dependencies are from `apt-cache showpkg roundcube-core`.
echo "Installing Roundcube (webmail)..."
apt_install \
	dbconfig-common \
	php5 php5-sqlite php5-mcrypt php5-intl php5-json php5-common php-auth php-net-smtp php-net-socket php-net-sieve php-mail-mime php-crypt-gpg php5-gd php5-pspell \
	tinymce libjs-jquery libjs-jquery-mousewheel libmagic1
apt_get_quiet remove php-mail-mimedecode # no longer needed since Roundcube 1.1.3

# We used to install Roundcube from Ubuntu, without triggering the dependencies #NODOC
# on Apache and MySQL, by downloading the debs and installing them manually. #NODOC
# Now that we're beyond that, get rid of those debs before installing from source. #NODOC
apt-get purge -qq -y roundcube* #NODOC

# Install Roundcube from source if it is not already present or if it is out of date.
# Combine the Roundcube version number with the commit hash of vacation_sieve to track
# whether we have the latest version.
VERSION=1.2.3
HASH=b0c3c4ba25596b2637c058b8254b58292755ec52
VACATION_SIEVE_VERSION=91ea6f52216390073d1f5b70b5f6bea0bfaee7e5
PERSISTENT_LOGIN_VERSION=1e9d724476a370ce917a2fcd5b3217b0c306c24e
HTML5_NOTIFIER_VERSION=4b370e3cd60dabd2f428a26f45b677ad1b7118d5
CARDDAV_VERSION=2.0.4
# sha1sum of the rcmcarddav plugin release
CARDDAV_HASH=d93f3cfb3038a519e71c7c3212c1d16f5da609a4

UPDATE_KEY=$VERSION:$VACATION_SIEVE_VERSION:$PERSISTENT_LOGIN_VERSION:$HTML5_NOTIFIER_VERSION:$CARDDAV_VERSION:a

# paths that are often reused.
RCM_DIR=/usr/local/lib/roundcubemail
RCM_PLUGIN_DIR=${RCM_DIR}/plugins
RCM_CONFIG=${RCM_DIR}/config/config.inc.php

needs_update=0 #NODOC
if [ ! -f /usr/local/lib/roundcubemail/version ]; then
	# not installed yet #NODOC
	needs_update=1 #NODOC
elif [[ "$UPDATE_KEY" != `cat /usr/local/lib/roundcubemail/version` ]]; then
	# checks if the version is what we want
	needs_update=1 #NODOC
fi
if [ $needs_update == 1 ]; then
	# install roundcube
	wget_verify \
		https://github.com/roundcube/roundcubemail/releases/download/$VERSION/roundcubemail-$VERSION.tar.gz \
		$HASH \
		/tmp/roundcube.tgz
	tar -C /usr/local/lib --no-same-owner -zxf /tmp/roundcube.tgz
	rm -rf /usr/local/lib/roundcubemail
	mv /usr/local/lib/roundcubemail-$VERSION/ $RCM_DIR
	rm -f /tmp/roundcube.tgz

	# install roundcube autoreply/vacation plugin
	git_clone https://github.com/arodier/Roundcube-Plugins.git $VACATION_SIEVE_VERSION plugins/vacation_sieve ${RCM_PLUGIN_DIR}/vacation_sieve

	# install roundcube persistent_login plugin
	git_clone https://github.com/mfreiholz/Roundcube-Persistent-Login-Plugin.git $PERSISTENT_LOGIN_VERSION '' ${RCM_PLUGIN_DIR}/persistent_login

	# install roundcube html5_notifier plugin
	git_clone https://github.com/kitist/html5_notifier.git $HTML5_NOTIFIER_VERSION '' ${RCM_PLUGIN_DIR}/html5_notifier

	# download and verify the full release of the carddav plugin
	wget_verify \
		https://github.com/blind-coder/rcmcarddav/releases/download/v${CARDDAV_VERSION}/carddav-${CARDDAV_VERSION}.zip \
		$CARDDAV_HASH \
		/tmp/carddav.zip

	# unzip and cleanup
	unzip -q /tmp/carddav.zip -d ${RCM_PLUGIN_DIR}
	rm -f /tmp/carddav.zip

	# record the version we've installed
	echo $UPDATE_KEY > ${RCM_DIR}/version
fi

# ### Configuring Roundcube

# Generate a safe 24-character secret key of safe characters.
SECRET_KEY=$(dd if=/dev/urandom bs=1 count=18 2>/dev/null | base64 | fold -w 24 | head -n 1)

# Create a configuration file.
#
# For security, temp and log files are not stored in the default locations
# which are inside the roundcube sources directory. We put them instead
# in normal places.
cat > $RCM_CONFIG <<EOF;
<?php
/*
 * Do not edit. Written by Mail-in-a-Box. Regenerated on updates.
 */
\$config = array();
\$config['log_dir'] = '/var/log/roundcubemail/';
\$config['temp_dir'] = '/tmp/roundcubemail/';
\$config['db_dsnw'] = 'sqlite:///$STORAGE_ROOT/mail/roundcube/roundcube.sqlite?mode=0640';
\$config['default_host'] = 'ssl://localhost';
\$config['default_port'] = 993;
\$config['imap_timeout'] = 15;
\$config['smtp_server'] = 'tls://127.0.0.1';
\$config['smtp_port'] = 587;
\$config['smtp_user'] = '%u';
\$config['smtp_pass'] = '%p';
\$config['support_url'] = 'https://mailinabox.email/';
\$config['product_name'] = '$PRIMARY_HOSTNAME Webmail';
\$config['des_key'] = '$SECRET_KEY';
\$config['plugins'] = array('html5_notifier', 'archive', 'zipdownload', 'password', 'managesieve', 'jqueryui', 'vacation_sieve', 'persistent_login', 'carddav');
\$config['skin'] = 'classic';
\$config['login_autocomplete'] = 2;
\$config['password_charset'] = 'UTF-8';
\$config['junk_mbox'] = 'Spam';
?>
EOF

# Configure CardDav
cat > ${RCM_PLUGIN_DIR}/carddav/config.inc.php <<EOF;
<?php
/* Do not edit. Written by Mail-in-a-Box. Regenerated on updates. */
\$prefs['ownCloud'] = array(
	 // required attributes
	 'name'         =>  'ownCloud',
	 // will be substituted for the roundcube username
	 'username'     =>  '%u',
	 // will be substituted for the roundcube password
	 'password'     =>  '%p',
	 // %u will be substituted for the CardDAV username
	 'url'          =>  'https://${PRIMARY_HOSTNAME}/cloud/remote.php/carddav/addressbooks/%u/contacts',
	 'active'       =>  true,
	 'readonly'     =>  false,
	 'refresh_time' => '02:00:00',
	 'fixed'        =>  array('username','password'),
	 'preemptive_auth' => '1',
	 'hide'        =>  false,
);
EOF

# Configure vaction_sieve.
cat > /usr/local/lib/roundcubemail/plugins/vacation_sieve/config.inc.php <<EOF;
<?php
/* Do not edit. Written by Mail-in-a-Box. Regenerated on updates. */
\$rcmail_config['vacation_sieve'] = array(
    'date_format' => 'd/m/Y',
    'working_hours' => array(8,18),
    'msg_format' => 'text',
    'logon_transform' => array('#([a-z])[a-z]+(\.|\s)([a-z])#i', '\$1\$3'),
    'transfer' => array(
        'mode' =>  'managesieve',
        'ms_activate_script' => true,
        'host'   => '127.0.0.1',
        'port'   => '4190',
        'usetls' => false,
        'path' => 'vacation',
    )
);
EOF

# Create writable directories.
mkdir -p /var/log/roundcubemail /tmp/roundcubemail $STORAGE_ROOT/mail/roundcube
chown -R www-data.www-data /var/log/roundcubemail /tmp/roundcubemail $STORAGE_ROOT/mail/roundcube

# Ensure the log file monitored by fail2ban exists, or else fail2ban can't start.
sudo -u www-data touch /var/log/roundcubemail/errors

# Password changing plugin settings
# The config comes empty by default, so we need the settings
# we're not planning to change in config.inc.dist...
cp ${RCM_PLUGIN_DIR}/password/config.inc.php.dist \
	${RCM_PLUGIN_DIR}/password/config.inc.php

tools/editconf.py ${RCM_PLUGIN_DIR}/password/config.inc.php \
	"\$config['password_minimum_length']=6;" \
	"\$config['password_db_dsn']='sqlite:///$STORAGE_ROOT/mail/users.sqlite';" \
	"\$config['password_query']='UPDATE users SET password=%D WHERE email=%u';" \
	"\$config['password_dovecotpw']='/usr/bin/doveadm pw';" \
	"\$config['password_dovecotpw_method']='SHA512-CRYPT';" \
	"\$config['password_dovecotpw_with_method']=true;"

# so PHP can use doveadm, for the password changing plugin
usermod -a -G dovecot www-data

# set permissions so that PHP can use users.sqlite
# could use dovecot instead of www-data, but not sure it matters
chown root.www-data $STORAGE_ROOT/mail
chmod 775 $STORAGE_ROOT/mail
chown root.www-data $STORAGE_ROOT/mail/users.sqlite
chmod 664 $STORAGE_ROOT/mail/users.sqlite

# Fix Carddav permissions:
chown -f -R root.www-data ${RCM_PLUGIN_DIR}/carddav
# root.www-data need all permissions, others only read
chmod -R 774 ${RCM_PLUGIN_DIR}/carddav

# Run Roundcube database migration script (database is created if it does not exist)
${RCM_DIR}/bin/updatedb.sh --dir ${RCM_DIR}/SQL --package roundcube
chown www-data:www-data $STORAGE_ROOT/mail/roundcube/roundcube.sqlite
chmod 664 $STORAGE_ROOT/mail/roundcube/roundcube.sqlite

# Enable PHP modules.
php5enmod mcrypt
restart_service php5-fpm
