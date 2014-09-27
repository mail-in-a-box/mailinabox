#!/bin/bash
#
# Postfix (SMTP)
# --------------
#
# Postfix handles the transmission of email between servers
# using the SMTP protocol. It is a Mail Transfer Agent (MTA).
#
# Postfix listens on port 25 (SMTP) for incoming mail from
# other servers on the Internet. It is responsible for very
# basic email filtering such as by IP address and greylisting,
# it checks that the destination address is valid, rewrites
# destinations according to aliases, and passses email on to
# another service for local mail delivery.
#
# The first hop in local mail delivery is to Spamassassin via
# LMTP. Spamassassin then passes mail over to Dovecot for
# storage in the user's mailbox.
#
# Postfix also listens on port 587 (SMTP+STARTLS) for
# connections from users who can authenticate and then sends
# their email out to the outside world. Postfix queries Dovecot
# to authenticate users.
#
# Address validation, alias rewriting, and user authentication
# is configured in a separate setup script mail-users.sh
# because of the overlap of this part with the Dovecot
# configuration.

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# ### Install packages.

apt_install postfix postgrey postfix-pcre ca-certificates

# ### Basic Settings

# Have postfix listen on all network interfaces, set our name (the Debian default seems to be localhost),
# and set the name of the local machine to localhost for xxx@localhost mail (but I don't think this will have any effect because
# there is no true local mail delivery). Also set the banner (must have the hostname first, then anything).
tools/editconf.py /etc/postfix/main.cf \
	inet_interfaces=all \
	myhostname=$PRIMARY_HOSTNAME\
	smtpd_banner="\$myhostname ESMTP Hi, I'm a Mail-in-a-Box (Ubuntu/Postfix; see https://mailinabox.email/)" \
	mydestination=localhost

# ### Outgoing Mail

# Enable the 'submission' port 587 smtpd server and tweak its settings.
#
# * Require the best ciphers for incoming connections per http://baldric.net/2013/12/07/tls-ciphers-in-postfix-and-dovecot/.
#   but without affecting opportunistic TLS on incoming mail, which will allow any cipher (it's better than none).
# * Give it a different name in syslog to distinguish it from the port 25 smtpd server.
# * Add a new cleanup service specific to the submission service ('authclean')
#   that filters out privacy-sensitive headers on mail being sent out by
#   authenticated users.
tools/editconf.py /etc/postfix/master.cf -s -w \
	"submission=inet n       -       -       -       -       smtpd
	  -o syslog_name=postfix/submission
	  -o smtpd_tls_ciphers=high -o smtpd_tls_protocols=!SSLv2,!SSLv3
	  -o cleanup_service_name=authclean" \
	"authclean=unix  n       -       -       -       0       cleanup
	  -o header_checks=pcre:/etc/postfix/outgoing_mail_header_filters"

# Install the `outgoing_mail_header_filters` file required by the new 'authclean' service.
cp conf/postfix_outgoing_mail_header_filters /etc/postfix/outgoing_mail_header_filters

# Enable relaying from TLS authenticated sibling hosts
# The smtpd_tls_CAfile is superflous, but it turns warnings in the logs about untrusted certs
# into notices about trusted certs. Since in these cases Postfix is checking the fingerprint,
# it does not care about whether the remote certificate is signed by a trusted CA. But,
# looking at the logs, it's nice to be able to see that it is.
# The CA file is provided by the package ca-certificates.
#
# To grant relay access to a sibling host, install and configure Postfix on that host as a
# smarthost and set relayhost to [yourbox.domain.tld]. Then add these three parameters to the
# sibling host's /etc/postfix/main.cf (there's no such parameter as smtp_tls_wrappermode so we
# have to use STARTTLS to port 25):
# smtp_use_tls=yes
# smtp_tls_cert_file=/etc/ssl/certs/yoursiblinghost.domain.tld.chain.pem
# smtp_tls_key_file=/etc/ssl/private/yoursiblinghost.domain.tld.key
#
# Since we only care about the fingerprint, the certificate can be self-signed - it will just
# be harmlessly logged as untrusted in the logs as per the above note about smtpd_tls_CAfile.
#
# Run:
# openssl x509 -noout -fingerprint -sha1 -in /etc/ssl/certs/yoursiblinghost.domain.tld.chain.pem
# to get the sibling host's public key fingerprint. Then on the mailinabox add an entry for that
# fingerprint to /home/user-data/mail/relayers/relay_clientcerts, for example:
# echo "B1:6A:87:2E:98:B6:BC:54:4F:6F:2D:98:0F:50:C3:43:AC:07:72:E7 yoursiblinghost.domain.tld" >> /home/user-data/mail/relayers/relay_clientcerts
#
# Finally, on the mailinabox run:
# postmap /home/user-data/mail/relayers/relay_clientcerts
#
# To test on the sibling host, ensure you have mailutils installed (sudo aptitude install
# mailutils) and then run something like:
# echo "" | mail -r "an_address_that_your_mailinabox_receives_for@domain.tld" -s "Test" "an_address_your_mailinabox_does_not_receive_for@gmail.com"
# where the e.g. gmail address is one you do actually have.
#
# If the configuration is correct you'll get a test email at the e.g. gmail.com address. If not,
# you should at least get a relay rejection error email at the domain.tld address.  Watching the
# box's logs should help diagnose any problems - to do so run:
# tail -f /var/log/mail.log
# To view the sibling host's queue you can use postqueue -p, and you can use postqueue -f to
# retrigger attempts to submit to the mailinabox.
#
# Be sure to create receiving accounts/aliases for all addresses that the sibling host(s) will
# send as!
tools/editconf.py /etc/postfix/main.cf \
	smtpd_tls_ask_ccert=yes \
	smtpd_tls_CAfile=/etc/ssl/certs/ca-certificates.crt \
	smtpd_tls_fingerprint_digest=sha1 \
	smtpd_tls_loglevel=2 \
	relay_clientcerts=hash:$STORAGE_ROOT/mail/relayers/relay_clientcerts

mkdir -p $STORAGE_ROOT/mail/relayers
if [[ ! -f $STORAGE_ROOT/mail/relayers/relay_clientcerts ]]; then
	touch $STORAGE_ROOT/mail/relayers/relay_clientcerts
	postmap /home/user-data/mail/relayers/relay_clientcerts
fi

# Enable TLS on these and all other connections (i.e. ports 25 *and* 587) and
# require TLS before a user is allowed to authenticate. This also makes
# opportunistic TLS available on *incoming* mail.
# Set stronger DH parameters, which via openssl tend to default to 1024 bits.
tools/editconf.py /etc/postfix/main.cf \
	smtpd_tls_security_level=may\
	smtpd_tls_auth_only=yes \
	smtpd_tls_cert_file=$STORAGE_ROOT/ssl/ssl_certificate.pem \
	smtpd_tls_key_file=$STORAGE_ROOT/ssl/ssl_private_key.pem \
	smtpd_tls_dh1024_param_file=$STORAGE_ROOT/ssl/dh2048.pem \
	smtpd_tls_received_header=yes

# Prevent non-authenticated users from sending mail that requires being
# relayed elsewhere. We don't want to be an "open relay". On outbound
# mail, require one of:
#
# * permit_tls_clientcerts: (TLS) authenticated sibling hosts (on port 25).
# * permit_sasl_authenticated: (Password) authenticated users (on port 587).
# * permit_mynetworks: Mail that originates locally.
# * reject_unauth_destination: No one else. (Permits mail whose destination is local and rejects other mail.)
tools/editconf.py /etc/postfix/main.cf \
	smtpd_relay_restrictions=permit_tls_clientcerts,permit_sasl_authenticated,permit_mynetworks,reject_unauth_destination


# ### DANE
#
# When connecting to remote SMTP servers, prefer TLS and use DANE if available.
#
# Prefering ("opportunistic") TLS means Postfix will accept whatever SSL certificate the remote
# end provides, if the remote end offers STARTTLS during the connection. DANE takes this a
# step further:
#
# Postfix queries DNS for the TLSA record on the destination MX host. If no TLSA records are found,
# then opportunistic TLS is used. Otherwise the server certificate must match the TLSA records
# or else the mail bounces. TLSA also requires DNSSEC on the MX host. Postfix doesn't do DNSSEC
# itself but assumes the system's nameserver does and reports DNSSEC status. Thus this also
# relies on our local bind9 server being present and smtp_dns_support_level being set to dnssec
# to use it.
#
# The smtp_tls_CAfile is superflous, but it turns warnings in the logs about untrusted certs
# into notices about trusted certs. Since in these cases Postfix is doing opportunistic TLS,
# it does not care about whether the remote certificate is trusted. But, looking at the logs,
# it's nice to be able to see that the connection was in fact encrypted for the right party.
# The CA file is provided by the package ca-certificates.
tools/editconf.py /etc/postfix/main.cf \
	smtp_tls_security_level=dane \
	smtp_dns_support_level=dnssec \
	smtp_tls_CAfile=/etc/ssl/certs/ca-certificates.crt \
	smtp_tls_loglevel=2

# ### Incoming Mail

# Pass any incoming mail over to a local delivery agent. Spamassassin
# will act as the LDA agent at first. It is listening on port 10025
# with LMTP. Spamassassin will pass the mail over to Dovecot after.
#
# In a basic setup we would pass mail directly to Dovecot by setting
# virtual_transport to `lmtp:unix:private/dovecot-lmtp`.
#
tools/editconf.py /etc/postfix/main.cf virtual_transport=lmtp:[127.0.0.1]:10025

# Who can send mail to us? Some basic filters.
#
# * reject_non_fqdn_sender: Reject not-nice-looking return paths.
# * reject_unknown_sender_domain: Reject return paths with invalid domains.
# * reject_rhsbl_sender: Reject return paths that use blacklisted domains.
# * permit_tls_clientcerts: (TLS) authenticated sibling hosts (on port 25) can skip further checks.
# * permit_sasl_authenticated: (Password) authenticated users (on port 587) can skip further checks.
# * permit_mynetworks: Mail that originates locally can skip further checks.
# * reject_rbl_client: Reject connections from IP addresses blacklisted in zen.spamhaus.org
# * reject_unlisted_recipient: Although Postfix will reject mail to unknown recipients, it's nicer to reject such mail ahead of greylisting rather than after.
# * check_policy_service: Apply greylisting using postgrey.
#
# Notes:
# permit_dnswl_client can pass through mail from whitelisted IP addresses, which would be good to put before greylisting
# so these IPs get mail delivered quickly. But when an IP is not listed in the permit_dnswl_client list (i.e. it is not
# whitelisted) then postfix does a DEFER_IF_REJECT, which results in all "unknown user" sorts of messages turning into
# "450 4.7.1 Client host rejected: Service unavailable". This is a retry code, so the mail doesn't properly bounce.
tools/editconf.py /etc/postfix/main.cf \
	smtpd_sender_restrictions="reject_non_fqdn_sender,reject_unknown_sender_domain,reject_rhsbl_sender dbl.spamhaus.org" \
	smtpd_recipient_restrictions=permit_tls_clientcerts,permit_sasl_authenticated,permit_mynetworks,"reject_rbl_client zen.spamhaus.org",reject_unlisted_recipient,"check_policy_service inet:127.0.0.1:10023"

# Increase the message size limit from 10MB to 128MB.
tools/editconf.py /etc/postfix/main.cf \
	message_size_limit=134217728

# Allow the two SMTP ports in the firewall.

ufw_allow smtp
ufw_allow submission

# Restart services

restart_service postfix
