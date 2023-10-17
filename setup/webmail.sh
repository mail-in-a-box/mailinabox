#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

# Webmail with Roundcube
# ----------------------

source setup/functions.sh # load our functions
source setup/functions-downloads.sh
source /etc/mailinabox.conf # load global vars
source ${STORAGE_ROOT}/ldap/miab_ldap.conf

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
	php${PHP_VER}-cli php${PHP_VER}-sqlite3 php${PHP_VER}-intl php${PHP_VER}-common php${PHP_VER}-curl php${PHP_VER}-imap \
	php${PHP_VER}-gd php${PHP_VER}-pspell php${PHP_VER}-mbstring libjs-jquery libjs-jquery-mousewheel libmagic1 \
	sqlite3

apt_install php${PHP_VER}-ldap

# Install Roundcube from source if it is not already present or if it is out of date.
# Combine the Roundcube version number with the commit hash of plugins to track
# whether we have the latest version of everything.
# For the latest versions, see:
#   https://github.com/roundcube/roundcubemail/releases
#   https://github.com/mfreiholz/persistent_login/commits/master
#   https://github.com/stremlau/html5_notifier/commits/master
#   https://github.com/mstilkerich/rcmcarddav/releases
# The easiest way to get the package hashes is to run this script and get the hash from
# the error message.
VERSION=1.6.4
HASH=bfc693d6590542d63171e6a3997fc29f0a5f12ca
PERSISTENT_LOGIN_VERSION=version-5.3.0
HTML5_NOTIFIER_VERSION=68d9ca194212e15b3c7225eb6085dbcf02fd13d7 # version 0.6.4+
CARDDAV_VERSION=4.4.3
CARDDAV_VERSION_AND_VARIANT=4.4.3
CARDDAV_HASH=74f8ba7aee33e78beb9de07f7f44b81f6071b644

UPDATE_KEY=$VERSION:$PERSISTENT_LOGIN_VERSION:$HTML5_NOTIFIER_VERSION:$CARDDAV_VERSION

# paths that are often reused.
RCM_DIR=/usr/local/lib/roundcubemail
RCM_PLUGIN_DIR=${RCM_DIR}/plugins
RCM_CONFIG=${RCM_DIR}/config/config.inc.php

needs_update=0 #NODOC
if [ ! -f /usr/local/lib/roundcubemail/version ]; then
	# not installed yet #NODOC
	needs_update=1 #NODOC
elif [[ "$UPDATE_KEY" != $(cat /usr/local/lib/roundcubemail/version) ]]; then
	# checks if the version is what we want
	needs_update=1 #NODOC
fi
if [ $needs_update == 1 ]; then
  # if upgrading from 1.3.x, clear the temp_dir
  if [ -f /usr/local/lib/roundcubemail/version ]; then
    if [ "$(cat /usr/local/lib/roundcubemail/version | cut -c1-3)" == '1.3' ]; then
      find /var/tmp/roundcubemail/ -type f ! -name 'RCMTEMP*' -delete
    fi
  fi

	# install roundcube
	wget_verify \
		https://github.com/roundcube/roundcubemail/releases/download/$VERSION/roundcubemail-$VERSION-complete.tar.gz \
		$HASH \
		/tmp/roundcube.tgz
	tar -C /usr/local/lib --no-same-owner -zxf /tmp/roundcube.tgz
	rm -rf /usr/local/lib/roundcubemail
	mv /usr/local/lib/roundcubemail-$VERSION/ $RCM_DIR
	rm -f /tmp/roundcube.tgz

	# install roundcube persistent_login plugin
	git_clone https://github.com/mfreiholz/Roundcube-Persistent-Login-Plugin.git $PERSISTENT_LOGIN_VERSION '' ${RCM_PLUGIN_DIR}/persistent_login

	# install roundcube html5_notifier plugin
	git_clone https://github.com/kitist/html5_notifier.git $HTML5_NOTIFIER_VERSION '' ${RCM_PLUGIN_DIR}/html5_notifier

	# download and verify the full release of the carddav plugin
	wget_verify \
		https://github.com/mstilkerich/rcmcarddav/releases/download/v${CARDDAV_VERSION}/carddav-v${CARDDAV_VERSION_AND_VARIANT}.tar.gz \
		$CARDDAV_HASH \
		/tmp/carddav.tar.gz

	# unzip and cleanup
	tar -C ${RCM_PLUGIN_DIR} -zxf /tmp/carddav.tar.gz
	rm -f /tmp/carddav.tar.gz

	# record the version we've installed
	echo $UPDATE_KEY > ${RCM_DIR}/version
fi

# ### TEMPORARY PATCHES

# vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
# REMOVE BELOW ONCE ROUNDCUBE INCLUDES A PEAR/NET_LDAP2 > 2.2.0
#
# Core php (>=8.0) changed the ldap ABI, which breaks the password
# plugin (which uses pear/net_ldap2 that itself calls the PHP ldap
# api). There is an unreleased, but accepted, fix that we apply here
# manually. see:
# https://github.com/pear/Net_LDAP2/commit/1cacdebcf6fe82718e5fa701c1ff688405e0f5d9
#
# The patch below is from github for the commit, which will presumably
# be included with the next net_ldap2 release.
#
# All this can be removed once the net_ldap2 library is released with
# the fix *AND* roundcube incorporates it with it's release (MIAB is
# not using composer).
if grep ldap_first_attribute "/usr/local/lib/roundcubemail/vendor/pear/net_ldap2/Net/LDAP2/Entry.php" | grep -F '$ber' >/dev/null; then
    patch -p1 --unified --quiet --directory=/usr/local/lib/roundcubemail/vendor/pear/net_ldap2 <$(pwd)/conf/roundcubemail/pear_net_ldap2.1cacdebcf6fe82718e5fa701c1ff688405e0f5d9.diff
elif [ $needs_update = 1 ]; then
    say_verbose "Reminder: it is safe to remove net_ldap2 patch applied by webmail.sh"
fi
# ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^


# ### Configuring Roundcube

# Generate a secret key of PHP-string-safe characters appropriate
# for the cipher algorithm selected below.
SECRET_KEY=$(dd if=/dev/urandom bs=1 count=32 2>/dev/null | base64 | sed s/=//g)

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
\$config['temp_dir'] = '/var/tmp/roundcubemail/';
\$config['db_dsnw'] = 'sqlite:///$STORAGE_ROOT/mail/roundcube/roundcube.sqlite?mode=0640';
\$config['imap_host'] = 'ssl://localhost:993';
\$config['imap_conn_options'] = array(
  'ssl'         => array(
     'verify_peer'  => false,
     'verify_peer_name'  => false,
   ),
 );
\$config['imap_timeout'] = 15;
\$config['smtp_host'] = 'tls://127.0.0.1:587';
\$config['smtp_conn_options'] = array(
  'ssl'         => array(
     'verify_peer'  => false,
     'verify_peer_name'  => false,
   ),
 );
\$config['support_url'] = 'https://mailinabox.email/';
\$config['product_name'] = '$PRIMARY_HOSTNAME Webmail';
\$config['cipher_method'] = 'AES-256-CBC'; # persistent login cookie and potentially other things
\$config['des_key'] = '$SECRET_KEY'; # 37 characters -> ~256 bits for AES-256, see above
\$config['plugins'] = array('html5_notifier', 'archive', 'zipdownload', 'password', 'managesieve', 'jqueryui', 'persistent_login', 'carddav');
\$config['skin'] = 'elastic';
\$config['login_autocomplete'] = 2;
\$config['login_username_filter'] = 'email';
\$config['password_charset'] = 'UTF-8';
\$config['junk_mbox'] = 'Spam';
// Session lifetime in minutes
\$config['session_lifetime'] = 60;
\$config['ldap_public']['public'] = array(
    'name'              => 'Directory',
    'hosts'             => array('${LDAP_URL}'),
    'user_specific'     => false,
    'scope'             => 'sub',
    'base_dn'           => '${LDAP_USERS_BASE}',
    'bind_dn'           => '${LDAP_WEBMAIL_DN}',
    'bind_pass'         => '${LDAP_WEBMAIL_PASSWORD}',
    'writable'          => false,
    'ldap_version'      => 3,
    'search_fields'     => array( 'mail', 'cn' ),
    'name_field'        => 'cn',
    'email_field'       => 'mail',
    'sort'              => 'cn',
    'filter'            => '(objectClass=mailUser)',
    'fuzzy_search'      => false,
    'global_search'     => true,
    # 'groups'            => array(
    #     'base_dn'         => '${LDAP_ALIASES_BASE}',
    #     'filter'          => '(objectClass=mailGroup)',
    # 	'member_attr'     => 'member',
    # 	'scope'           => 'sub',
    # 	'name_attr'       => 'mail',
    # 	'member_filter'   => '(|(objectClass=mailGroup)(objectClass=mailUser))',
    # )
);

/* ensure roudcube session id's aren't leaked to other parts of the server */
\$config['session_path'] = '/mail/';

/* prevent CSRF, requires php 7.3+ */
\$config['session_samesite'] = 'Strict';
?>
EOF

# Configure CardDav
cat > ${RCM_PLUGIN_DIR}/carddav/config.inc.php <<EOF;
<?php
/* Do not edit. Written by Mail-in-a-Box. Regenerated on updates. */
\$prefs['_GLOBAL']['hide_preferences'] = true;
\$prefs['_GLOBAL']['suppress_version_warning'] = true;
\$prefs['ownCloud'] = array(
	 'name'         =>  'ownCloud',
	 'username'     =>  '%u', // login username
	 'password'     =>  '%p', // login password
	 'url'          =>  'https://${PRIMARY_HOSTNAME}/cloud/remote.php/dav/addressbooks/users/%u/contacts/',
	 'active'       =>  true,
	 'readonly'     =>  false,
	 'refresh_time' => '02:00:00',
	 'fixed'        =>  array('username','password'),
	 'preemptive_auth' => '1',
	 'hide'        =>  false,
);
?>
EOF

# Configure persistent_login (required database tables are created
# later in this script)
cat > ${RCM_PLUGIN_DIR}/persistent_login/config.inc.php <<EOF
<?php
/* Do not edit. Written by Mail-in-a-Box. Regenerated on updates. */
\$rcmail_config['ifpl_use_auth_tokens'] = true;  # enable AuthToken cookies
?>
EOF

# Create writable directories.
mkdir -p /var/log/roundcubemail /var/tmp/roundcubemail $STORAGE_ROOT/mail/roundcube
chown -R www-data:www-data /var/log/roundcubemail /var/tmp/roundcubemail $STORAGE_ROOT/mail/roundcube

# Ensure the log file monitored by fail2ban exists, or else fail2ban can't start.
sudo -u www-data touch /var/log/roundcubemail/errors.log

# Password changing plugin settings
# The config comes empty by default, so we need the settings
# we're not planning to change in config.inc.dist...
cp ${RCM_PLUGIN_DIR}/password/config.inc.php.dist \
	${RCM_PLUGIN_DIR}/password/config.inc.php

tools/editconf.py ${RCM_PLUGIN_DIR}/password/config.inc.php \
	"\$config['password_driver']='ldap_simple';" \
	"\$config['password_ldap_host']='${LDAP_SERVER}';" \
	"\$config['password_ldap_port']=${LDAP_SERVER_PORT};" \
	"\$config['password_ldap_starttls']=$([ ${LDAP_SERVER_STARTTLS} == yes ] && echo true || echo false);" \
	"\$config['password_ldap_basedn']='${LDAP_BASE}';" \
	"\$config['password_ldap_userDN_mask']=null;" \
	"\$config['password_ldap_searchDN']='${LDAP_WEBMAIL_DN}';" \
	"\$config['password_ldap_searchPW']='${LDAP_WEBMAIL_PASSWORD}';" \
	"\$config['password_ldap_search_base']='${LDAP_USERS_BASE}';" \
	"\$config['password_ldap_search_filter']='(&(objectClass=mailUser)(mail=%login))';" \
	"\$config['password_ldap_encodage']='default';" \
	"\$config['password_ldap_lchattr']='shadowLastChange';" \
	"\$config['password_algorithm']='sha512-crypt';" \
	"\$config['password_algorithm_prefix']='{CRYPT}';" \
	"\$config['password_minimum_length']=8;"

# Fix Carddav permissions:
chown -f -R root:www-data ${RCM_PLUGIN_DIR}/carddav
# root:www-data need all permissions, others only read
chmod -R 774 ${RCM_PLUGIN_DIR}/carddav

# Run Roundcube database migration script (database is created if it does not exist)
php$PHP_VER ${RCM_DIR}/bin/updatedb.sh --dir ${RCM_DIR}/SQL --package roundcube
chown www-data:www-data $STORAGE_ROOT/mail/roundcube/roundcube.sqlite
chmod 664 $STORAGE_ROOT/mail/roundcube/roundcube.sqlite

# Create persistent login plugin's database tables
sqlite3 $STORAGE_ROOT/mail/roundcube/roundcube.sqlite < ${RCM_PLUGIN_DIR}/persistent_login/sql/sqlite.sql

# Enable PHP modules.
phpenmod -v $PHP_VER imap ldap
restart_service php$PHP_VER-fpm

# Periodically clean the roundcube database (see roundcubemail/INSTALL)
cat > /etc/cron.daily/mailinabox-roundcubemail << EOF
#!/bin/bash
# Mail-in-a-Box
# Clean up the roundcube database
cd $RCM_DIR && bin/cleandb.sh >/dev/null
EOF
chmod +x /etc/cron.daily/mailinabox-roundcubemail

