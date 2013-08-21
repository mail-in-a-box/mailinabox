# Install OpenDKIM.
#
# After this, you'll still need to run dns_update to get the DKIM
# signature in the DNS zones.

apt-get install -q -y opendkim opendkim-tools

mkdir -p /etc/opendkim;
mkdir -p $STORAGE_ROOT/mail/dkim

echo "127.0.0.1" > /etc/opendkim/TrustedHosts

if grep -q "ExternalIgnoreList" /etc/opendkim.conf; then
	true; # already done
else
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

# Create a new DKIM key if we don't have one already.
if [ ! -z "$STORAGE_ROOT/mail/dkim/mail.private" ]; then
	# Should we specify -h rsa-sha256?
	opendkim-genkey -r -s mail -D $STORAGE_ROOT/mail/dkim
fi

chown -R opendkim:opendkim $STORAGE_ROOT/mail/dkim
chmod go-rwx $STORAGE_ROOT/mail/dkim

# add OpenDKIM as a milter to postfix. Be careful. If we add other milters
# later, it needs to be concatenated on the smtpd_milters line.
tools/editconf.py /etc/postfix/main.cf \
	smtpd_milters=inet:127.0.0.1:8891 \
	non_smtpd_milters=\$smtpd_milters \
	milter_default_action=accept

service opendkim restart
service postfix restart

