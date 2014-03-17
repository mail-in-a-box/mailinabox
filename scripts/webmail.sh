# Webmail: Using roundcube
##########################

source /etc/mailinabox.conf # load global vars

DEBIAN_FRONTEND=noninteractive apt-get -q -q -y install \
	roundcube-core php5-sqlite

# The version of roundcube shipped with Ubuntu is really out of date so we'll
# now upgrade the packages. We do it this way so the other dependencies are
# pulled in via apt for us automatically.
mkdir -p externals
pkg_ver=0.9.5-4_all
wget -nc -P externals http://ftp.debian.org/debian/pool/main/r/roundcube/{roundcube,roundcube-core,roundcube-sqlite3,roundcube-plugins}_$pkg_ver.deb
DEBIAN_FRONTEND=noninteractive dpkg -Gi externals/{roundcube,roundcube-core,roundcube-sqlite3,roundcube-plugins}_$pkg_ver.deb

# Buuuut.... the .deb is missing things?
src_fn=roundcube_0.9.5.orig.tar.gz
src_dir=roundcubemail-0.9.5-dep
wget -nc -P externals http://ftp.debian.org/debian/pool/main/r/roundcube/$src_fn
tar -C /tmp -xzf $(pwd)/externals/$src_fn
if [ ! -d /usr/share/roundcube/SQL ]; then mv /tmp/$src_dir/SQL/ /usr/share/roundcube/; fi
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
	"\$rcmail_config['draft_autosave']=30;"


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

