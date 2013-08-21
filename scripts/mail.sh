# Configures a postfix SMTP server and dovecot IMAP server.
#
# We configure these together because postfix delivers mail
# directly to dovecot, so they basically rely on each other.

# Install packages.

sudo DEBIAN_FRONTEND=noninteractive apt-get install -q -y \
	postfix postgrey dovecot-core dovecot-imapd dovecot-lmtpd dovecot-sqlite

# POSTFIX

mkdir -p $STORAGE_ROOT/mail
	
# TLS configuration
sudo sed -i "s/#submission/submission/" /etc/postfix/master.cf # enable submission port (not in Drew Crawford's instructions)
sudo tools/editconf.py /etc/postfix/main.cf \
	smtpd_use_tls=yes\
	smtpd_tls_auth_only=yes \
	smtp_tls_security_level=may \
	smtp_tls_loglevel=2 \
	smtpd_tls_received_header=yes
	
	# note: smtpd_use_tls=yes appears to already be the default, but we can never be too sure

# authorization via dovecot
sudo tools/editconf.py /etc/postfix/main.cf \
	smtpd_sasl_type=dovecot \
	smtpd_sasl_path=private/auth \
	smtpd_sasl_auth_enable=yes \
	smtpd_recipient_restrictions=permit_sasl_authenticated,permit_mynetworks,reject_unauth_destination

sudo tools/editconf.py /etc/postfix/main.cf mydestination=localhost

# message delivery is directly to dovecot
sudo tools/editconf.py /etc/postfix/main.cf virtual_transport=lmtp:unix:private/dovecot-lmtp

# domain and user table is configured in a Sqlite3 database
sudo tools/editconf.py /etc/postfix/main.cf \
	virtual_mailbox_domains=sqlite:/etc/postfix/virtual-mailbox-domains.cf \
	virtual_mailbox_maps=sqlite:/etc/postfix/virtual-mailbox-maps.cf \
	virtual_alias_maps=sqlite:/etc/postfix/virtual-alias-maps.cf \
	local_recipient_maps=\$virtual_mailbox_maps

db_path=$STORAGE_ROOT/mail/users.sqlite

sudo su root -c "cat > /etc/postfix/virtual-mailbox-domains.cf" << EOF;
dbpath=$db_path
query = SELECT 1 FROM users WHERE email LIKE '%%@%s'
EOF

sudo su root -c "cat > /etc/postfix/virtual-mailbox-maps.cf" << EOF;
dbpath=$db_path
query = SELECT 1 FROM users WHERE email='%s'
EOF

sudo su root -c "cat > /etc/postfix/virtual-alias-maps.cf" << EOF;
dbpath=$db_path
query = SELECT destination FROM aliases WHERE source='%s'
EOF

# create an empty mail users database if it doesn't yet exist

if [ ! -f $db_path ]; then
	echo Creating new user database: $db_path;
	echo "CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, email TEXT NOT NULL UNIQUE, password TEXT NOT NULL, extra);" | sqlite3 $db_path;
	echo "CREATE TABLE aliases (id INTEGER PRIMARY KEY AUTOINCREMENT, source TEXT NOT NULL UNIQUE, destination TEXT NOT NULL);" | sqlite3 $db_path;
fi

# DOVECOT

# The dovecot-imapd dovecot-lmtpd packages automatically enable those protocols.

# mail storage location
sudo tools/editconf.py /etc/dovecot/conf.d/10-mail.conf \
	mail_location=maildir:$STORAGE_ROOT/mail/mailboxes/%d/%n \
	mail_privileged_group=mail \
	first_valid_uid=0

# authentication mechanisms
sudo tools/editconf.py /etc/dovecot/conf.d/10-auth.conf \
	disable_plaintext_auth=yes \
	"auth_mechanisms=plain login"

# use SQL-based authentication, not the system users
sudo sed -i "s/\(\!include auth-system.conf.ext\)/#\1/"  /etc/dovecot/conf.d/10-auth.conf
sudo sed -i "s/#\(\!include auth-sql.conf.ext\)/\1/"  /etc/dovecot/conf.d/10-auth.conf

# how to access SQL
sudo su root -c "cat > /etc/dovecot/conf.d/auth-sql.conf.ext" << EOF;
passdb {
  driver = sql
  args = /etc/dovecot/dovecot-sql.conf.ext
}
userdb {
  driver = static
  args = uid=mail gid=mail home=$STORAGE_ROOT/mail/mailboxes/%d/%n
}
EOF
sudo su root -c "cat > /etc/dovecot/dovecot-sql.conf.ext" << EOF;
driver = sqlite
connect = $db_path
default_pass_scheme = SHA512-CRYPT
password_query = SELECT email as user, password FROM users WHERE email='%u';
EOF

# disable in-the-clear IMAP and POP because we're paranoid (we haven't even
# enabled POP).
sudo sed -i "s/#port = 143/port = 0/" /etc/dovecot/conf.d/10-master.conf
sudo sed -i "s/#port = 110/port = 0/" /etc/dovecot/conf.d/10-master.conf

# Modify the unix socket for LMTP.
sudo sed -i "s/unix_listener lmtp \(.*\)/unix_listener \/var\/spool\/postfix\/private\/dovecot-lmtp \1\n    user = postfix\n    group = postfix\n/" /etc/dovecot/conf.d/10-master.conf 

# Add an additional auth socket for postfix. Check if it already is
# set to make sure this is idempotent.
if sudo grep -q "mailinabox-postfix-private-auth" /etc/dovecot/conf.d/10-master.conf; then
	# already done
	true;
else
	sudo sed -i "s/\(\s*unix_listener auth-userdb\)/  unix_listener \/var\/spool\/postfix\/private\/auth \{ # mailinabox-postfix-private-auth\n    mode = 0666\n    user = postfix\n    group = postfix\n  \}\n\1/" /etc/dovecot/conf.d/10-master.conf
fi

# Drew Crawford sets the auth-worker process to run as the mail user, but we don't care if it runs as root.

# Enable SSL.
sudo tools/editconf.py /etc/dovecot/conf.d/10-ssl.conf \
	ssl=required \
	"ssl_cert=<$STORAGE_ROOT/ssl/ssl_certificate.pem" \
	"ssl_key=<$STORAGE_ROOT/ssl/ssl_private_key.pem" \
	
# The Dovecot installation already created a self-signed public/private key pair
# in /etc/dovecot/dovecot.pem and /etc/dovecot/private/dovecot.pem, which we'll
# use unless certificates already exist.
mkdir -p $STORAGE_ROOT/ssl
if [ ! -f $STORAGE_ROOT/ssl/ssl_certificate.pem ]; then sudo cp /etc/dovecot/dovecot.pem $STORAGE_ROOT/ssl/ssl_certificate.pem; fi
if [ ! -f $STORAGE_ROOT/ssl/ssl_private_key.pem ]; then sudo cp /etc/dovecot/private/dovecot.pem $STORAGE_ROOT/ssl/ssl_private_key.pem; fi

sudo chown -R mail:dovecot /etc/dovecot
sudo chmod -R o-rwx /etc/dovecot

mkdir -p $STORAGE_ROOT/mail/mailboxes
sudo chown -R mail.mail $STORAGE_ROOT/mail/mailboxes

# restart services
sudo service postfix restart
sudo service dovecot restart

# allow mail-related ports in the firewall
sudo ufw allow smtp
sudo ufw allow submission
sudo ufw allow imaps


