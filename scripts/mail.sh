# Configures a postfix SMTP server and dovecot IMAP server.
#
# We configure these together because postfix delivers mail
# directly to dovecot, so they basically rely on each other.

# Install packages.

DEBIAN_FRONTEND=noninteractive apt-get install -q -y \
	postfix postgrey \
	dovecot-core dovecot-imapd dovecot-lmtpd dovecot-sqlite sqlite3

# POSTFIX

mkdir -p $STORAGE_ROOT/mail

# TLS configuration
sed -i "s/#submission/submission/" /etc/postfix/master.cf # enable submission port (not in Drew Crawford's instructions)
tools/editconf.py /etc/postfix/main.cf \
	smtpd_use_tls=yes\
	smtpd_tls_auth_only=yes \
	smtp_tls_security_level=may \
	smtp_tls_loglevel=2 \
	smtpd_tls_received_header=yes
	
	# note: smtpd_use_tls=yes appears to already be the default, but we can never be too sure

# authorization via dovecot
tools/editconf.py /etc/postfix/main.cf \
	smtpd_sasl_type=dovecot \
	smtpd_sasl_path=private/auth \
	smtpd_sasl_auth_enable=yes

# Who can send outbound mail?
# permit_sasl_authenticated: Authenticated users (i.e. on port 587).
# permit_mynetworks: Mail that originates locally.
# reject_unauth_destination: No one else. (Permits mail whose destination is local and rejects other mail.)
tools/editconf.py /etc/postfix/main.cf \
	smtpd_relay_restrictions=permit_sasl_authenticated,permit_mynetworks,reject_unauth_destination

# Who can send mail to us?
# permit_sasl_authenticated: Authenticated users (i.e. on port 587).
# permit_mynetworks: Mail that originates locally.
# reject_rbl_client: Reject connections from IP addresses blacklisted in zen.spamhaus.org
# check_policy_service: Apply greylisting using postgrey.
tools/editconf.py /etc/postfix/main.cf \
	smtpd_recipient_restrictions=permit_sasl_authenticated,permit_mynetworks,"reject_rbl_client zen.spamhaus.org","check_policy_service inet:127.0.0.1:10023"

tools/editconf.py /etc/postfix/main.cf \
	inet_interfaces=all \
	mydestination=localhost

# message delivery is directly to dovecot
tools/editconf.py /etc/postfix/main.cf virtual_transport=lmtp:unix:private/dovecot-lmtp

# domain and user table is configured in a Sqlite3 database
tools/editconf.py /etc/postfix/main.cf \
	virtual_mailbox_domains=sqlite:/etc/postfix/virtual-mailbox-domains.cf \
	virtual_mailbox_maps=sqlite:/etc/postfix/virtual-mailbox-maps.cf \
	virtual_alias_maps=sqlite:/etc/postfix/virtual-alias-maps.cf \
	local_recipient_maps=\$virtual_mailbox_maps

db_path=$STORAGE_ROOT/mail/users.sqlite

cat > /etc/postfix/virtual-mailbox-domains.cf << EOF;
dbpath=$db_path
query = SELECT 1 FROM users WHERE email LIKE '%%@%s'
EOF

cat > /etc/postfix/virtual-mailbox-maps.cf << EOF;
dbpath=$db_path
query = SELECT 1 FROM users WHERE email='%s'
EOF

cat > /etc/postfix/virtual-alias-maps.cf << EOF;
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
tools/editconf.py /etc/dovecot/conf.d/10-mail.conf \
	mail_location=maildir:$STORAGE_ROOT/mail/mailboxes/%d/%n \
	mail_privileged_group=mail \
	first_valid_uid=0

# authentication mechanisms
tools/editconf.py /etc/dovecot/conf.d/10-auth.conf \
	disable_plaintext_auth=yes \
	"auth_mechanisms=plain login"

# use SQL-based authentication, not the system users
sed -i "s/\(\!include auth-system.conf.ext\)/#\1/"  /etc/dovecot/conf.d/10-auth.conf
sed -i "s/#\(\!include auth-sql.conf.ext\)/\1/"  /etc/dovecot/conf.d/10-auth.conf

# how to access SQL
cat > /etc/dovecot/conf.d/auth-sql.conf.ext << EOF;
passdb {
  driver = sql
  args = /etc/dovecot/dovecot-sql.conf.ext
}
userdb {
  driver = static
  args = uid=mail gid=mail home=$STORAGE_ROOT/mail/mailboxes/%d/%n
}
EOF
cat > /etc/dovecot/dovecot-sql.conf.ext << EOF;
driver = sqlite
connect = $db_path
default_pass_scheme = SHA512-CRYPT
password_query = SELECT email as user, password FROM users WHERE email='%u';
EOF

# disable in-the-clear IMAP and POP because we're paranoid (we haven't even
# enabled POP).
sed -i "s/#port = 143/port = 0/" /etc/dovecot/conf.d/10-master.conf
sed -i "s/#port = 110/port = 0/" /etc/dovecot/conf.d/10-master.conf

# Create a Unix domain socket specific for postgres for auth and LMTP because
# postgres is more easily configured to use these locations, and create a TCP socket
# for spampd to inject mail on (if it's configured later). dovecot's standard
# lmtp unix socket is also listening.
cat > /etc/dovecot/conf.d/99-local.conf << EOF;
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0666
    user = postfix
    group = postfix
  }
}
service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    user = postfix
    group = postfix
  }
  inet_listener lmtp {
    address = 127.0.0.1
    port = 10026
  }
}
EOF

# Drew Crawford sets the auth-worker process to run as the mail user, but we don't care if it runs as root.

# Enable SSL.
tools/editconf.py /etc/dovecot/conf.d/10-ssl.conf \
	ssl=required \
	"ssl_cert=<$STORAGE_ROOT/ssl/ssl_certificate.pem" \
	"ssl_key=<$STORAGE_ROOT/ssl/ssl_private_key.pem" \
	
# The Dovecot installation already created a self-signed public/private key pair
# in /etc/dovecot/dovecot.pem and /etc/dovecot/private/dovecot.pem, which we'll
# use unless certificates already exist.
mkdir -p $STORAGE_ROOT/ssl
if [ ! -f $STORAGE_ROOT/ssl/ssl_certificate.pem ]; then cp /etc/dovecot/dovecot.pem $STORAGE_ROOT/ssl/ssl_certificate.pem; fi
if [ ! -f $STORAGE_ROOT/ssl/ssl_private_key.pem ]; then cp /etc/dovecot/private/dovecot.pem $STORAGE_ROOT/ssl/ssl_private_key.pem; fi

chown -R mail:dovecot /etc/dovecot
chmod -R o-rwx /etc/dovecot

mkdir -p $STORAGE_ROOT/mail/mailboxes
chown -R mail.mail $STORAGE_ROOT/mail/mailboxes

# restart services
service postfix restart
service dovecot restart

# allow mail-related ports in the firewall
ufw allow smtp
ufw allow submission
ufw allow imaps


