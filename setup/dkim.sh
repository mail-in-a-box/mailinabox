#!/bin/bash
# DKIM
# --------
#
# DKIMpy provides a service that puts a DKIM signature on outbound mail.
#
# The DNS configuration for DKIM is done in the management daemon.

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# Remove openDKIM if present
apt-get purge -qq -y opendkim opendkim-tools

# Install DKIMpy-Milter
echo Installing DKIMpy/OpenDMARC...
apt_install dkimpy-milter python3-dkim opendmarc

# Make sure configuration directories exist.
mkdir -p /etc/dkim;
mkdir -p $STORAGE_ROOT/mail/dkim

# Used in InternalHosts and ExternalIgnoreList configuration directives.
# Not quite sure why.
echo "127.0.0.1" > /etc/dkim/TrustedHosts

# We need to at least create these files, since we reference them later.
touch /etc/dkim/KeyTable
touch /etc/dkim/SigningTable

tools/editconf.py /etc/dkimpy-milter/dkimpy-milter.conf -s \
    "MacroList=daemon_name|ORIGINATING" \
    "MacroListVerify=daemon_name|VERIFYING" \
    "Canonicalization=relaxed/simple" \
    "MinimumKeyBits=1024" \
    "InternalHosts=refile:/etc/dkim/TrustedHosts" \
    "KeyTable=refile:/etc/dkim/KeyTable" \
    "KeyTableEd25519=refile:/etc/dkim/KeyTableEd25519" \
    "SigningTable=refile:/etc/dkim/SigningTable" \
    "Socket=inet:8892@127.0.0.1"

# Create a new DKIM key. This creates mail.key and mail.dns
# in $STORAGE_ROOT/mail/dkim. The former is the private key and
# the latter is the suggested DNS TXT entry which we'll include
# in our DNS setup. Note that the files are named after the
# 'selector' of the key, which we can change later on to support
# key rotation.
if [ ! -f "$STORAGE_ROOT/mail/dkim/mail.key" ]; then
	# Check if there is an existing rsa key
	if [ -f "$STORAGE_ROOT/mail/dkim/mail.private" ]; then
		# Re-use existing key
		cp -f $STORAGE_ROOT/mail/dkim/mail.private $STORAGE_ROOT/mail/dkim/mail.key
		cp -f $STORAGE_ROOT/mail/dkim/mail.txt $STORAGE_ROOT/mail/dkim/mail.dns
	else
		# All defaults are supposed to be ok, default key for rsa is 2048 bit
		dknewkey --ktype rsa $STORAGE_ROOT/mail/dkim/mail
		# Change format from pkcs#8 to pkcs#1, dkimpy seemingly is not able to handle the #8 format
		# See bug https://bugs.launchpad.net/dkimpy/+bug/1978835
		openssl pkey -in $STORAGE_ROOT/mail/dkim/mail.key -traditional -out $STORAGE_ROOT/mail/dkim/mail.key.1
		mv -f $STORAGE_ROOT/mail/dkim/mail.key $STORAGE_ROOT/mail/dkim/mail.key.8
		cp -f $STORAGE_ROOT/mail/dkim/mail.key.1 $STORAGE_ROOT/mail/dkim/mail.key
		
		# Force dns entry into the format dns_update.py expects
		# We use selector mail for the rsa key, to be compatible with earlier installations of Mail-in-a-Box
		sed -i 's/v=DKIM1;/mail._domainkey IN      TXT      ( "v=DKIM1; s=email;/' $STORAGE_ROOT/mail/dkim/mail.dns
		echo '" )' >> $STORAGE_ROOT/mail/dkim/mail.dns
	fi
fi

if [ ! -f "$STORAGE_ROOT/mail/dkim/box-ed25519.key" ]; then
	# Generate ed25519 key
	dknewkey --ktype ed25519 $STORAGE_ROOT/mail/dkim/box-ed25519
	
	# For the ed25519 dns entry, we use selector box-ed25519
	sed -i 's/v=DKIM1;/box-ed25519._domainkey IN      TXT      ( "v=DKIM1; s=email;/' $STORAGE_ROOT/mail/dkim/box-ed25519.dns
	echo '" )' >> $STORAGE_ROOT/mail/dkim/box-ed25519.dns
fi

# Ensure files are owned by the dkimpy-milter user and are private otherwise.
chown -R dkimpy-milter:dkimpy-milter $STORAGE_ROOT/mail/dkim
chmod go-rwx $STORAGE_ROOT/mail/dkim

tools/editconf.py /etc/opendmarc.conf -s \
	"Syslog=true" \
	"Socket=inet:8893@[127.0.0.1]" \
	"FailureReports=true"

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

# Enables generation of failure reports for sending domains that publish a
# "none" policy.

tools/editconf.py /etc/opendmarc.conf -s \
        "FailureReportsOnNone=true"

# Add DKIMpy and OpenDMARC as milters to postfix, which is how DKIMpy
# intercepts outgoing mail to perform the signing (by adding a mail header)
# and how they both intercept incoming mail to add Authentication-Results
# headers. The order possibly/probably matters: OpenDMARC relies on the
# DKIM Authentication-Results header already being present.
#
# Be careful. If we add other milters later, this needs to be concatenated
# on the smtpd_milters line.
#
# The OpenDMARC milter is skipped in the SMTP submission listener by
# configuring smtpd_milters there to only list the DKIMpy milter
# (see mail-postfix.sh).
tools/editconf.py /etc/postfix/main.cf \
	"smtpd_milters=inet:127.0.0.1:8892 inet:127.0.0.1:8893"\
	non_smtpd_milters=\$smtpd_milters \
	milter_default_action=accept

# We need to explicitly enable the opendmarc service, or it will not start
hide_output systemctl enable opendmarc

# Restart services.
restart_service dkimpy-milter
restart_service opendmarc
restart_service postfix

