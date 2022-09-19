#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

#
# User Authentication and Destination Validation
# ----------------------------------------------
#
# This script configures user authentication for Dovecot
# and Postfix (which relies on Dovecot) and destination
# validation by quering a ldap database of mail users.

# LDAP helpful links:
#   http://www.postfix.org/LDAP_README.html
#   http://www.postfix.org/postconf.5.html
#   http://www.postfix.org/ldap_table.5.html
#

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars
source ${STORAGE_ROOT}/ldap/miab_ldap.conf # user-data specific vars

# ### User Authentication

# Have Dovecot query our database, and not system users, for authentication.
sed -i "s/#*\(\!include auth-system.conf.ext\)/#\1/"  /etc/dovecot/conf.d/10-auth.conf
sed -i "s/#*\(\!include auth-sql.conf.ext\)/#\1/"  /etc/dovecot/conf.d/10-auth.conf
sed -i "s/#\(\!include auth-ldap.conf.ext\)/\1/"  /etc/dovecot/conf.d/10-auth.conf


# Specify how the database is to be queried for user authentication (passdb)
# and where user mailboxes are stored (userdb).
cat > /etc/dovecot/conf.d/auth-ldap.conf.ext << EOF;
passdb {
  driver = ldap
  args = /etc/dovecot/dovecot-ldap.conf.ext
}
userdb {
  driver = ldap
  args = /etc/dovecot/dovecot-userdb-ldap.conf.ext
  default_fields = uid=mail gid=mail home=$STORAGE_ROOT/mail/mailboxes/%d/%n
}
EOF

# Dovecot ldap configuration
cat > /etc/dovecot/dovecot-ldap.conf.ext << EOF;
# LDAP server(s) to connect to
uris = ${LDAP_URL}
tls = ${LDAP_SERVER_TLS}

# Credentials dovecot uses to perform searches
dn = ${LDAP_DOVECOT_DN}
dnpass = ${LDAP_DOVECOT_PASSWORD}

# Use ldap authentication binding for verifying users' passwords
# otherwise we have to give dovecot admin access to the database
# so it can read userPassword, which is less secure
auth_bind = yes
# default_pass_scheme = SHA512-CRYPT

# Search base (subtree)
base = ${LDAP_USERS_BASE}

# Find the user:
#   Dovecot uses its service account to search for the user using the
#   filter below. If found, the user is authenticated against this dn
#   (a bind is attempted as that user). The attribute 'mail' is
#   multi-valued and contains all the user's email addresses. We use
#   maildrop as the dovecot mailbox address and forbid them from using
#   it for authentication by excluding maildrop from the filter.
pass_filter = (&(objectClass=mailUser)(mail=%u))
pass_attrs = maildrop=user

# Apply per-user settings:
#   Post-login information specific to the user (eg. quotas).  For
#   lmtp delivery, pass_filter is not used, and postfix has already
#   rewritten the envelope using the maildrop address.
user_filter = (&(objectClass=mailUser)(|(mail=%u)(maildrop=%u)))
user_attrs = maildrop=user

# Account iteration for various dovecot tools (doveadm)
iterate_filter = (objectClass=mailUser)
iterate_attrs = maildrop=user

EOF
chmod 0600 /etc/dovecot/dovecot-ldap.conf.ext # per Dovecot instructions

# symlink userdb ext file per dovecot instructions
ln -sf /etc/dovecot/dovecot-ldap.conf.ext /etc/dovecot/dovecot-userdb-ldap.conf.ext

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

#
# And have Postfix use that service. We *disable* it here
# so that authentication is not permitted on port 25 (which
# does not run DKIM on relayed mail, so outbound mail isn't
# correct, see #830), but we enable it specifically for the
# submission port.
tools/editconf.py /etc/postfix/main.cf \
	smtpd_sasl_type=dovecot \
	smtpd_sasl_path=private/auth \
	smtpd_sasl_auth_enable=no

# ### Sender Validation

# We use Postfix's reject_authenticated_sender_login_mismatch filter to
# prevent intra-domain spoofing by logged in but untrusted users in outbound
# email. In all outbound mail (the sender has authenticated), the MAIL FROM
# address (aka envelope or return path address) must be "owned" by the user
# who authenticated.
#
# sender-login-maps is given a FROM address (%s), which it uses to
# obtain all the users that are permitted to MAIL FROM that address
# (from the docs: "Optional lookup table with the SASL login names
# that own the sender (MAIL FROM) addresses")
# see: http://www.postfix.org/postconf.5.html
#
# With multiple lookup tables specified, the first matching lookup
# ends the search. So, if there is a permitted-senders ldap group,
# alias group memberships are not considered for inclusion that may
# MAIL FROM the FROM address being searched for.
tools/editconf.py /etc/postfix/main.cf \
	smtpd_sender_login_maps="ldap:/etc/postfix/sender-login-maps-explicit.cf, ldap:/etc/postfix/sender-login-maps-aliases.cf"


# FROM addresses with an explicit list of "permitted senders"
cat > /etc/postfix/sender-login-maps-explicit.cf <<EOF
server_host = ${LDAP_URL}
bind = yes
bind_dn = ${LDAP_POSTFIX_DN}
bind_pw = ${LDAP_POSTFIX_PASSWORD}
version = 3
search_base = ${LDAP_PERMITTED_SENDERS_BASE}
query_filter = (mail=%s)
result_attribute = maildrop
special_result_attribute = member
EOF
# protect the password
chgrp postfix /etc/postfix/sender-login-maps-explicit.cf
chmod 0640 /etc/postfix/sender-login-maps-explicit.cf

# Users may MAIL FROM any of their own aliases
cat > /etc/postfix/sender-login-maps-aliases.cf <<EOF
server_host = ${LDAP_URL}
bind = yes
bind_dn = ${LDAP_POSTFIX_DN}
bind_pw = ${LDAP_POSTFIX_PASSWORD}
version = 3
search_base = ${LDAP_USERS_BASE}
query_filter = (mail=%s)
result_attribute = maildrop
special_result_attribute = member
EOF
chgrp postfix /etc/postfix/sender-login-maps-aliases.cf
chmod 0640 /etc/postfix/sender-login-maps-aliases.cf


# ### Destination Validation

# Check whether a destination email address exists, and to perform any
# email alias rewrites in Postfix.
tools/editconf.py /etc/postfix/main.cf \
	smtputf8_enable=no \
	virtual_mailbox_domains=ldap:/etc/postfix/virtual-mailbox-domains.cf \
	virtual_mailbox_maps=ldap:/etc/postfix/virtual-mailbox-maps.cf \
	virtual_alias_maps=ldap:/etc/postfix/virtual-alias-maps.cf \
	local_recipient_maps=\$virtual_mailbox_maps


# the domains we handle mail for
cat > /etc/postfix/virtual-mailbox-domains.cf << EOF
server_host = ${LDAP_URL}
bind = yes
bind_dn = ${LDAP_POSTFIX_DN}
bind_pw = ${LDAP_POSTFIX_PASSWORD}
version = 3
search_base = ${LDAP_BASE}
query_filter = (|(&(objectClass=mailDomain)(|(dc=%s)(dcIntl=%s)))(&(objectClass=mailGroup)(mail=@%s)(&(!(member=*))(!(mailMember=*)))))
result_attribute = objectClass
EOF
chgrp postfix /etc/postfix/virtual-mailbox-domains.cf
chmod 0640 /etc/postfix/virtual-mailbox-domains.cf

# check if we handle incoming mail for a user.
# (this doesn't seem to ever be used by postfix)
cat > /etc/postfix/virtual-mailbox-maps.cf << EOF
server_host = ${LDAP_URL}
bind = yes
bind_dn = ${LDAP_POSTFIX_DN}
bind_pw = ${LDAP_POSTFIX_PASSWORD}
version = 3
search_base = ${LDAP_USERS_BASE}
query_filter = (&(objectClass=mailUser)(mail=%s)(!(|(maildrop="*|*")(maildrop="*:*")(maildrop="*/*"))))
result_attribute = maildrop
EOF
chgrp postfix /etc/postfix/virtual-mailbox-maps.cf
chmod 0640 /etc/postfix/virtual-mailbox-maps.cf



# Rewrite an email address if an alias is present.
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

#
# This is the ldap version of aliases(5) but for virtual
# addresses. Postfix queries this recursively to determine delivery
# addresses. Aliases may be addresses, domains, and catch-alls.
# 
cat > /etc/postfix/virtual-alias-maps.cf <<EOF
server_host = ${LDAP_URL}
bind = yes
bind_dn = ${LDAP_POSTFIX_DN}
bind_pw = ${LDAP_POSTFIX_PASSWORD}
version = 3
search_base = ${LDAP_USERS_BASE}
query_filter = (mail=%s)
result_attribute = maildrop, mailMember
special_result_attribute = member
EOF
chgrp postfix /etc/postfix/virtual-alias-maps.cf
chmod 0640 /etc/postfix/virtual-alias-maps.cf

# Restart Services
##################

restart_service postfix
restart_service dovecot

