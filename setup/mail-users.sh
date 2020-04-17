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
	echo "CREATE TABLE aliases (id INTEGER PRIMARY KEY AUTOINCREMENT, source TEXT NOT NULL UNIQUE, destination TEXT NOT NULL, permitted_senders TEXT);" | sqlite3 $db_path;
fi

# ### User Authentication

# Have Dovecot query our database, and not system users, for authentication.
sed -i "s/#*\(\!include auth-system.conf.ext\)/#\1/"  /etc/dovecot/conf.d/10-auth.conf
sed -i "s/#\(\!include auth-sql.conf.ext\)/\1/"  /etc/dovecot/conf.d/10-auth.conf

# Specify how the database is to be queried for user authentication (passdb)
# and where user mailboxes are stored (userdb).
cat > /etc/dovecot/conf.d/auth-sql.conf.ext << EOF;
passdb {
  driver = sql
  args = /etc/dovecot/dovecot-sql.conf.ext
}
userdb {
  driver = sql
  args = /etc/dovecot/dovecot-sql.conf.ext
}
EOF

# Configure the SQL to query for a user's metadata and password.
cat > /etc/dovecot/dovecot-sql.conf.ext << EOF;
driver = sqlite
connect = $db_path
default_pass_scheme = SHA512-CRYPT
password_query = SELECT email as user, password FROM users WHERE email='%u';
user_query = SELECT email AS user, "mail" as uid, "mail" as gid, "$STORAGE_ROOT/mail/mailboxes/%d/%n" as home FROM users WHERE email='%u';
iterate_query = SELECT email AS user FROM users;
EOF
chmod 0600 /etc/dovecot/dovecot-sql.conf.ext # per Dovecot instructions

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

# And have Postfix use that service. We *disable* it here
# so that authentication is not permitted on port 25 (which
# does not run DKIM on relayed mail, so outbound mail isn't
# correct, see #830), but we enable it specifically for the
# submission port.
management/editconf.py /etc/postfix/main.cf \
	smtpd_sasl_type=dovecot \
	smtpd_sasl_path=private/auth \
	smtpd_sasl_auth_enable=no

# ### Sender Validation

# We use Postfix's reject_authenticated_sender_login_mismatch filter to
# prevent intra-domain spoofing by logged in but untrusted users in outbound
# email. In all outbound mail (the sender has authenticated), the MAIL FROM
# address (aka envelope or return path address) must be "owned" by the user
# who authenticated. An SQL query will find who are the owners of any given
# address.
management/editconf.py /etc/postfix/main.cf \
	smtpd_sender_login_maps=sqlite:/etc/postfix/sender-login-maps.cf

# Postfix will query the exact address first, where the priority will be alias
# records first, then user records. If there are no matches for the exact
# address, then Postfix will query just the domain part, which we call
# catch-alls and domain aliases. A NULL permitted_senders column means to
# take the value from the destination column.
cat > /etc/postfix/sender-login-maps.cf << EOF;
dbpath=$db_path
query = SELECT permitted_senders FROM (SELECT permitted_senders, 0 AS priority FROM aliases WHERE source='%s' AND permitted_senders IS NOT NULL UNION SELECT destination AS permitted_senders, 1 AS priority FROM aliases WHERE source='%s' AND permitted_senders IS NULL UNION SELECT email as permitted_senders, 2 AS priority FROM users WHERE email='%s') ORDER BY priority LIMIT 1;
EOF

# ### Destination Validation

# Use a Sqlite3 database to check whether a destination email address exists,
# and to perform any email alias rewrites in Postfix.
management/editconf.py /etc/postfix/main.cf \
	virtual_mailbox_domains=sqlite:/etc/postfix/virtual-mailbox-domains.cf \
	virtual_mailbox_maps=sqlite:/etc/postfix/virtual-mailbox-maps.cf \
	virtual_alias_maps=sqlite:/etc/postfix/virtual-alias-maps.cf \
	local_recipient_maps=\$virtual_mailbox_maps

# SQL statement to check if we handle incoming mail for a domain, either for users or aliases.
cat > /etc/postfix/virtual-mailbox-domains.cf << EOF;
dbpath=$db_path
query = SELECT 1 FROM users WHERE email LIKE '%%@%s' UNION SELECT 1 FROM aliases WHERE source LIKE '%%@%s'
EOF

# SQL statement to check if we handle incoming mail for a user.
cat > /etc/postfix/virtual-mailbox-maps.cf << EOF;
dbpath=$db_path
query = SELECT 1 FROM users WHERE email='%s'
EOF

# SQL statement to rewrite an email address if an alias is present.
#
# Postfix makes multiple queries for each incoming mail. It first
# queries the whole email address, then just the user part in certain
# locally-directed cases (but we don't use this), then just `@`+the
# domain part. The first query that returns something wins. See
# http://www.postfix.org/virtual.5.html.
#
# virtual-alias-maps has precedence over virtual-mailbox-maps, but
# we don't want catch-alls and domain aliases to catch mail for users
# that have been defined on those domains. To fix this, we not only
# query the aliases table but also the users table when resolving
# aliases, i.e. we turn users into aliases from themselves to
# themselves. That means users will match in postfix's first query
# before postfix gets to the third query for catch-alls/domain alises.
#
# If there is both an alias and a user for the same address either
# might be returned by the UNION, so the whole query is wrapped in
# another select that prioritizes the alias definition to preserve
# postfix's preference for aliases for whole email addresses.
#
# Since we might have alias records with an empty destination because
# it might have just permitted_senders, skip any records with an
# empty destination here so that other lower priority rules might match.
cat > /etc/postfix/virtual-alias-maps.cf << EOF;
dbpath=$db_path
query = SELECT destination from (SELECT destination, 0 as priority FROM aliases WHERE source='%s' AND destination<>'' UNION SELECT email as destination, 1 as priority FROM users WHERE email='%s') ORDER BY priority LIMIT 1;
EOF

# Restart Services
##################

restart_service postfix
restart_service dovecot


