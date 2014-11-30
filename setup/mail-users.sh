#!/bin/bash
#
# User Authentication and Destination Validation
# ----------------------------------------------
#
# This script configures user authentication for Dovecot
# and Postfix (which relies on Dovecot) and destination
# validation by quering an Sqlite3 database of mail users. 

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# ### User and Alias Database

# The database of mail users (i.e. authenticated users, who have mailboxes)
# and aliases (forwarders).

db_path=$STORAGE_ROOT/mail/users.sqlite

# Create an empty database if it doesn't yet exist.
if [ ! -f $db_path ]; then
	echo Creating new user database: $db_path;
	echo "CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, email TEXT NOT NULL UNIQUE, password TEXT NOT NULL, extra, privileges TEXT NOT NULL DEFAULT '');" | sqlite3 $db_path;
	echo "CREATE TABLE aliases (id INTEGER PRIMARY KEY AUTOINCREMENT, source TEXT NOT NULL UNIQUE, destination TEXT NOT NULL);" | sqlite3 $db_path;
fi

# ### User Authentication

# Disable all of the built-in authentication mechanisms. (We formerly uncommented
# a line to include auth-sql.conf.ext but we no longer use that.)
sed -i "s/#*\(\!include auth-.*.conf.ext\)/#\1/"  /etc/dovecot/conf.d/10-auth.conf

# Legacy: Delete our old sql conf files.
rm -f /etc/dovecot/conf.d/auth-sql.conf.ext /etc/dovecot/dovecot-sql.conf.ext

# Specify how Dovecot should perform user authentication (passdb) and how it knows
# where user mailboxes are stored (userdb).
#
# For passwords, we would normally have Dovecot query our mail user database
# directly. The way to do that is commented out below. Instead, in order to
# provide our own authentication framework so we can handle two-factor auth,
# we will use a custom system that hooks into the Mail-in-a-Box management daemon.
#
# The user part of this is standard. The mailbox path and Unix system user are the
# same for all mail users, modulo string substitution for the mailbox path that
# Dovecot handles.
cat > /etc/dovecot/conf.d/10-auth-mailinabox.conf << EOF;
passdb {
  driver = checkpassword
  args = /usr/local/bin/dovecot-checkpassword
}
userdb {
  driver = static
  args = uid=mail gid=mail home=$STORAGE_ROOT/mail/mailboxes/%d/%n
}
EOF
chmod 0600 /etc/dovecot/conf.d/10-auth-mailinabox.conf

# Copy dovecot-checkpassword into place.
cp conf/dovecot-checkpassword.py /usr/local/bin/dovecot-checkpassword
chown dovecot.dovecot /usr/local/bin/dovecot-checkpassword
chmod 700 /usr/local/bin/dovecot-checkpassword

# If we were having Dovecot query our database directly, which we did
# originally, `/etc/dovecot/conf.d/10-auth-mailinabox.conf` would say:
#
#     passdb {
#       driver = sql
#       args = /etc/dovecot/dovecot-sql.conf.ext
#     }
#
# and then `/etc/dovecot/dovecot-sql.conf.ext` (chmod 0600) would contain:
#
#    driver = sqlite
#    connect = $db_path
#    default_pass_scheme = SHA512-CRYPT
#    password_query = SELECT email as user, password FROM users WHERE email='%u';

# Have Dovecot provide an authorization service that Postfix can access & use.
cat > /etc/dovecot/conf.d/99-local-auth.conf << EOF;
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0666
    user = postfix
    group = postfix
  }
}
EOF

# And have Postfix use that service.
tools/editconf.py /etc/postfix/main.cf \
	smtpd_sasl_type=dovecot \
	smtpd_sasl_path=private/auth \
	smtpd_sasl_auth_enable=yes

# ### Destination Validation

# Use a Sqlite3 database to check whether a destination email address exists,
# and to perform any email alias rewrites in Postfix.
tools/editconf.py /etc/postfix/main.cf \
	virtual_mailbox_domains=sqlite:/etc/postfix/virtual-mailbox-domains.cf \
	virtual_mailbox_maps=sqlite:/etc/postfix/virtual-mailbox-maps.cf \
	virtual_alias_maps=sqlite:/etc/postfix/virtual-alias-maps.cf \
	local_recipient_maps=\$virtual_mailbox_maps

# SQL statement to check if we handle mail for a domain, either for users or aliases.
cat > /etc/postfix/virtual-mailbox-domains.cf << EOF;
dbpath=$db_path
query = SELECT 1 FROM users WHERE email LIKE '%%@%s' UNION SELECT 1 FROM aliases WHERE source LIKE '%%@%s'
EOF

# SQL statement to check if we handle mail for a user.
cat > /etc/postfix/virtual-mailbox-maps.cf << EOF;
dbpath=$db_path
query = SELECT 1 FROM users WHERE email='%s'
EOF

# SQL statement to rewrite an email address if an alias is present.
# Aliases have precedence over users, but that's counter-intuitive for
# catch-all aliases ("@domain.com") which should *not* catch mail users.
# To fix this, not only query the aliases table but also the users
# table, i.e. turn users into aliases from themselves to themselves.
# If there is both an alias and a user for the same address either
# might be returned by the UNION, so the whole query is wrapped in
# another select that prioritizes the alias definition.
cat > /etc/postfix/virtual-alias-maps.cf << EOF;
dbpath=$db_path
query = SELECT destination from (SELECT destination, 0 as priority FROM aliases WHERE source='%s' UNION SELECT email as destination, 1 as priority FROM users WHERE email='%s') ORDER BY priority LIMIT 1;
EOF

# Restart Services
##################

restart_service postfix
restart_service dovecot


