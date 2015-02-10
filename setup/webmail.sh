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
apt_install \
	dbconfig-common \
	php5 php5-sqlite php5-mcrypt php5-intl php5-json php5-common php-auth php-net-smtp php-net-socket php-net-sieve php-mail-mime php-crypt-gpg php5-gd php5-pspell \
	tinymce libjs-jquery libjs-jquery-mousewheel libmagic1

# We used to install Roundcube from Ubuntu, without triggering the dependencies #NODOC
# on Apache and MySQL, by downloading the debs and installing them manually. #NODOC
# Now that we're beyond that, get rid of those debs before installing from source. #NODOC
apt-get purge -qq -y roundcube* #NODOC

# Install Roundcube from source if it is not already present or if it is out of date.
VERSION=1.0.3
needs_update=0 #NODOC
if [ ! -f /usr/local/lib/roundcubemail/version ]; then
	# not installed yet #NODOC
	needs_update=1 #NODOC
elif [[ $VERSION != `cat /usr/local/lib/roundcubemail/version` ]]; then
	# checks if the version is what we want
	needs_update=1 #NODOC
fi
if [ $needs_update == 1 ]; then
	echo installing roundcube webmail $VERSION...
	rm -f /tmp/roundcube.tgz
	wget -qO /tmp/roundcube.tgz http://downloads.sourceforge.net/project/roundcubemail/roundcubemail/$VERSION/roundcubemail-$VERSION.tar.gz
	tar -C /usr/local/lib -zxf /tmp/roundcube.tgz
	rm -rf /usr/local/lib/roundcubemail
	mv /usr/local/lib/roundcubemail-$VERSION/ /usr/local/lib/roundcubemail
	rm -f /tmp/roundcube.tgz
	echo $VERSION > /usr/local/lib/roundcubemail/version
fi

# ### Configuring Roundcube

# Generate a safe 24-character secret key of safe characters.
SECRET_KEY=$(dd if=/dev/random bs=1 count=18 2>/dev/null | base64 | fold -w 24 | head -n 1)

# Create a configuration file.
#
# For security, temp and log files are not stored in the default locations
# which are inside the roundcube sources directory. We put them instead
# in normal places.
cat > /usr/local/lib/roundcubemail/config/config.inc.php <<EOF;
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
\$config['smtp_server'] = 'tls://localhost';
\$config['smtp_port'] = 587;
\$config['smtp_user'] = '%u';
\$config['smtp_pass'] = '%p';
\$config['support_url'] = 'https://mailinabox.email/';
\$config['product_name'] = 'Mail-in-a-Box/Roundcube Webmail';
\$config['des_key'] = '$SECRET_KEY';
\$config['plugins'] = array('archive', 'zipdownload', 'password', 'managesieve');
\$config['skin'] = 'classic';
\$config['login_autocomplete'] = 2;
\$config['password_charset'] = 'UTF-8';
\$config['junk_mbox'] = 'Spam';
?>
EOF

# Create writable directories.
mkdir -p /var/log/roundcubemail /tmp/roundcubemail $STORAGE_ROOT/mail/roundcube
chown -R www-data.www-data /var/log/roundcubemail /tmp/roundcubemail $STORAGE_ROOT/mail/roundcube

# Password changing plugin settings
# The config comes empty by default, so we need the settings 
# we're not planning to change in config.inc.dist...
cp /usr/local/lib/roundcubemail/plugins/password/config.inc.php.dist \
	/usr/local/lib/roundcubemail/plugins/password/config.inc.php

tools/editconf.py /usr/local/lib/roundcubemail/plugins/password/config.inc.php \
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

# Enable PHP modules.
php5enmod mcrypt
restart_service php5-fpm
