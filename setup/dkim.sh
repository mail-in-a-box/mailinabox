#!/bin/bash
# OpenDKIM
# --------
#
# OpenDKIM provides a service that puts a DKIM signature on outbound mail.
#
# The DNS configuration for DKIM is done in the management daemon.

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# Install DKIM...
echo Installing OpenDKIM/OpenDMARC...
apt_install opendkim opendkim-tools opendmarc

# Make sure configuration directories exist.
mkdir -p /etc/opendkim;
mkdir -p $STORAGE_ROOT/mail/dkim

# Used in InternalHosts and ExternalIgnoreList configuration directives.
# Not quite sure why.
echo "127.0.0.1" > /etc/opendkim/TrustedHosts

# We need to at least create these files, since we reference them later.
# Otherwise, opendkim startup will fail
touch /etc/opendkim/KeyTable
touch /etc/opendkim/SigningTable

if grep -q "ExternalIgnoreList" /etc/opendkim.conf; then
	true # already done #NODOC
else
	# Add various configuration options to the end of `opendkim.conf`.
	cat >> /etc/opendkim.conf << EOF;
Canonicalization		relaxed/simple
MinimumKeyBits          1024
ExternalIgnoreList      refile:/etc/opendkim/TrustedHosts
InternalHosts           refile:/etc/opendkim/TrustedHosts
KeyTable                refile:/etc/opendkim/KeyTable
SigningTable            refile:/etc/opendkim/SigningTable
Socket                  inet:8891@127.0.0.1
RequireSafeKeys         false
EOF
fi

# Create a new DKIM key. This creates mail.private and mail.txt
# in $STORAGE_ROOT/mail/dkim. The former is the private key and
# the latter is the suggested DNS TXT entry which we'll include
# in our DNS setup. Note that the files are named after the
# 'selector' of the key, which we can change later on to support
# key rotation.
#
# A 1024-bit key is seen as a minimum standard by several providers
# such as Google. But they and others use a 2048 bit key, so we'll
# do the same. Keys beyond 2048 bits may exceed DNS record limits.
if [ ! -f "$STORAGE_ROOT/mail/dkim/mail.private" ]; then
	opendkim-genkey -b 2048 -r -s mail -D $STORAGE_ROOT/mail/dkim
fi

# Ensure files are owned by the opendkim user and are private otherwise.
chown -R opendkim:opendkim $STORAGE_ROOT/mail/dkim
chmod go-rwx $STORAGE_ROOT/mail/dkim

tools/editconf.py /etc/opendmarc.conf -s \
	"Syslog=true" \
	"Socket=inet:8893@[127.0.0.1]" \
	"FailureReports=false"

# SPFIgnoreResults causes the filter to ignore any SPF results in the header
# of the message. This is useful if you want the filter to perfrom SPF checks
# itself, or because you don't trust the arriving header. This added header is
# used by spamassassin to evaluate the mail for spamminess.

tools/editconf.py /etc/opendmarc.conf -s \
        "SPFIgnoreResults=true"

# SPFSelfValidate causes the filter to perform a fallback SPF check itself
# when it can find no SPF results in the message header. If SPFIgnoreResults
# is also set, it never looks for SPF results in headers and always performs
# the SPF check itself when this is set. This added header is used by
# spamassassin to evaluate the mail for spamminess.

tools/editconf.py /etc/opendmarc.conf -s \
        "SPFSelfValidate=true"

# Disables generation of failure reports for sending domains that publish a
# "none" policy.

tools/editconf.py /etc/opendmarc.conf -s \
        "FailureReportsOnNone=false"

# AlwaysAddARHeader Adds an "Authentication-Results:" header field even to
# unsigned messages from domains with no "signs all" policy. The reported DKIM
# result will be  "none" in such cases. Normally unsigned mail from non-strict
# domains does not cause the results header field to be added. This added header
# is used by spamassassin to evaluate the mail for spamminess.

tools/editconf.py /etc/opendkim.conf -s \
        "AlwaysAddARHeader=true"

# Add OpenDKIM and OpenDMARC as milters to postfix, which is how OpenDKIM
# intercepts outgoing mail to perform the signing (by adding a mail header)
# and how they both intercept incoming mail to add Authentication-Results
# headers. The order possibly/probably matters: OpenDMARC relies on the
# OpenDKIM Authentication-Results header already being present.
#
# Be careful. If we add other milters later, this needs to be concatenated
# on the smtpd_milters line.
#
# The OpenDMARC milter is skipped in the SMTP submission listener by
# configuring smtpd_milters there to only list the OpenDKIM milter
# (see mail-postfix.sh).
tools/editconf.py /etc/postfix/main.cf \
	"smtpd_milters=inet:127.0.0.1:8891 inet:127.0.0.1:8893"\
	non_smtpd_milters=\$smtpd_milters \
	milter_default_action=accept

# We need to explicitly enable the opendmarc service, or it will not start
hide_output systemctl enable opendmarc

# Restart services.
restart_service opendkim
restart_service opendmarc
restart_service postfix

