# OpenDKIM: Sign outgoing mail with DKIM
########################################

# After this, you'll still need to run dns_update.sh to get the DKIM
# signature in the DNS zones.

source setup/functions.sh # load our functions

# Install DKIM
apt_install opendkim opendkim-tools

# Make sure configuration directories exist.
mkdir -p /etc/opendkim;
mkdir -p $STORAGE_ROOT/mail/dkim

# Used in InternalHosts and ExternalIgnoreList configuration directives.
# Not quite sure why.
echo "127.0.0.1" > /etc/opendkim/TrustedHosts

if grep -q "ExternalIgnoreList" /etc/opendkim.conf; then
	true; # already done
else
	# Add various configuration options to the end.
	cat >> /etc/opendkim.conf << EOF;
MinimumKeyBits          1024
ExternalIgnoreList      refile:/etc/opendkim/TrustedHosts
InternalHosts           refile:/etc/opendkim/TrustedHosts
KeyTable                refile:/etc/opendkim/KeyTable
SigningTable            refile:/etc/opendkim/SigningTable
Socket                  inet:8891@localhost
RequireSafeKeys         false
EOF
fi

# Create a new DKIM key if we don't have one already. This creates
# mail.private and mail.txt in $STORAGE_ROOT/mail/dkim. The former
# is the actual private key and the latter is the suggested DNS TXT
# entry which we'll want to include in our DNS setup.
if [ ! -f "$STORAGE_ROOT/mail/dkim/mail.private" ]; then
	# Should we specify -h rsa-sha256?
	opendkim-genkey -r -s mail -D $STORAGE_ROOT/mail/dkim
fi

# Ensure files are owned by the opendkim user and are private otherwise.
chown -R opendkim:opendkim $STORAGE_ROOT/mail/dkim
chmod go-rwx $STORAGE_ROOT/mail/dkim

# Add OpenDKIM as a milter to postfix, which is how it intercepts outgoing
# mail to perform the signing (by adding a mail header).
# Be careful. If we add other milters later, it needs to be concatenated on the smtpd_milters line.
tools/editconf.py /etc/postfix/main.cf \
	smtpd_milters=inet:127.0.0.1:8891 \
	non_smtpd_milters=\$smtpd_milters \
	milter_default_action=accept

# Restart services.
restart_service opendkim
restart_service postfix

