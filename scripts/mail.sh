# Configures a postfix SMTP server.

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y postfix postgrey

# TLS configuration
sudo tools/editconf.py /etc/postfix/main.cf \
	smtpd_tls_auth_only=yes \
	smtp_tls_security_level=may \
	smtp_tls_loglevel=2 \
	smtpd_tls_received_header=yes

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

db_path=/home/ubuntu/storage/mail.sqlite
	
sudo su root -c "cat > /etc/postfix/virtual-mailbox-domains.cf" << EOF;
dbpath=$db_path
query = SELECT 1 FROM users WHERE email LIKE '@%s'
EOF

sudo su root -c "cat > /etc/postfix/virtual-mailbox-maps.cf" << EOF;
dbpath=$db_path
query = SELECT 1 FROM users WHERE email='%s'
EOF

sudo su root -c "cat > /etc/postfix/virtual-alias-maps.cf" << EOF;
dbpath=$db_path
query = SELECT destination FROM aliases WHERE source='%s'
EOF

# re-start postfix
sudo service postfix restart

# allow ports in the firewall
sudo ufw allow smtpd
sudo ufw allow submission


