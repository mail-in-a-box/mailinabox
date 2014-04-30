# Webmail: Using roundcube
##########################

source /etc/mailinabox.conf # load global vars

# Ubuntu's roundcube-core has a dependency on Apache & MySQL, which we don't want, so we can't
# install roundcube directly via apt-get install. We'll use apt-get to manually install the
# dependencies of roundcube that we know we need, and then we'll manually install debs for the
# roundcube version we want from Debian.
#
# 'DEBIAN_FRONTEND=noninteractive' is to prevent dbconfig-common from asking you questions.
# The dependencies are from 'apt-cache showpkg roundcube-core'.

DEBIAN_FRONTEND=noninteractive apt-get -q -q -y install \
	dbconfig-common \
	php5 php5-sqlite php5-mcrypt php5-intl php5-json php5-common php-auth php-net-smtp php-net-socket php-net-sieve php-mail-mime php-crypt-gpg php5-gd php5-pspell \
	tinymce libjs-jquery libjs-jquery-mousewheel libmagic1

mkdir -p externals
pkg_ver=0.9.5-4_all
wget -nc -P externals http://ftp.debian.org/debian/pool/main/r/roundcube/{roundcube,roundcube-core,roundcube-sqlite3,roundcube-plugins}_$pkg_ver.deb
DEBIAN_FRONTEND=noninteractive dpkg -Gi externals/{roundcube,roundcube-core,roundcube-sqlite3,roundcube-plugins}_$pkg_ver.deb

# Buuuut.... the .deb is missing things?
src_fn=roundcube_0.9.5.orig.tar.gz
src_dir=roundcubemail-0.9.5-dep
wget -nc -P externals http://ftp.debian.org/debian/pool/main/r/roundcube/$src_fn
tar -C /tmp -xzf $(pwd)/externals/$src_fn
if [ ! -d /var/lib/roundcube/SQL ]; then mv /tmp/$src_dir/SQL/ /var/lib/roundcube/; fi
rm -rf /tmp/$src_dir

# Settings
tools/editconf.py /etc/roundcube/main.inc.php \
	"\$rcmail_config['default_host']='ssl://localhost';" \
	"\$rcmail_config['default_port']=993;" \
	"\$rcmail_config['imap_timeout']=30;" \
	"\$rcmail_config['smtp_server']='tls://localhost';"\
	"\$rcmail_config['smtp_user']='%u';"\
	"\$rcmail_config['smtp_pass']='%p';"\
	"\$rcmail_config['smtp_timeout']=30;" \
	"\$rcmail_config['use_https']=true;" \
	"\$rcmail_config['session_lifetime']=60*24*3;" \
	"\$rcmail_config['password_charset']='utf8';" \
	"\$rcmail_config['message_sort_col']='arrival';" \
	"\$rcmail_config['junk_mbox']='Spam';" \
	"\$rcmail_config['default_folders']=array('INBOX', 'Drafts', 'Sent', 'Spam', 'Trash');" \
	"\$rcmail_config['draft_autosave']=30;" \
	"\$rcmail_config['plugins']=array('password');"

# Password changing plugin settings
# The config comes empty by default, so we need the settings 
# we're not planning to change in config.inc.dist...
cp /usr/share/roundcube/plugins/password/config.inc.php.dist \
	/etc/roundcube/plugins/password/config.inc.php 

tools/editconf.py /etc/roundcube/plugins/password/config.inc.php \
	"\$rcmail_config['password_minimum_length']=6;" \
	"\$rcmail_config['password_db_dsn']='sqlite:////home/user-data/mail/users.sqlite';" \
	"\$rcmail_config['password_query']='UPDATE users SET password=%D WHERE email=%u';" \
	"\$rcmail_config['password_dovecotpw']='/usr/bin/doveadm pw';" \
	"\$rcmail_config['password_dovecotpw_method']='SHA512-CRYPT';" \
	"\$rcmail_config['password_dovecotpw_with_method']=true;"

# Configure storage of user preferences.
mkdir -p $STORAGE_ROOT/mail/roundcube
cat - > /etc/roundcube/debian-db.php <<EOF;
<?php
\$dbtype = 'sqlite';
\$basepath = '$STORAGE_ROOT/mail/roundcube';
\$dbname = 'roundcube.sqlite';
?>
EOF
chown -R www-data.www-data $STORAGE_ROOT/mail/roundcube

# so PHP can use doveadm
usermod -a -G dovecot www-data

# set permissions so that PHP can use users.sqlite
# could use dovecot instead of www-data, but not sure it matters
chown root.www-data $STORAGE_ROOT/mail
chmod 775 $STORAGE_ROOT/mail
chown root.www-data $STORAGE_ROOT/mail/users.sqlite 
chmod 664 $STORAGE_ROOT/mail/users.sqlite 

# Enable PHP modules.
php5enmod mcrypt
service php-fastcgi restart
