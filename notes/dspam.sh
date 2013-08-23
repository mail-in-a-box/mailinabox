# Spam filtering with dspam.
#
# This mostly works. But dspam crashes. So..... we're not using this.

apt-get -q -y install dspam libdspam7-drv-sqlite3 dovecot-antispam dovecot-sieve

# Let it turn on.
sed -i "s/START=no/START=yes/" /etc/default/dspam 

# Override some of the basic settings that have default values we don't like.
# Listen as an SMTP server, and pass messages back directly to dovecot.
tools/editconf.py /etc/dspam/dspam.conf -s \
	Home=$STORAGE_ROOT/mail/dspam \
	ServerMode=standard \
	ServerHost=127.0.0.1 \
	ServerParameters=--deliver=innocent \
	DeliveryProto=LMTP \
	DeliveryHost=/var/run/dovecot/lmtp \
	Tokenizer=osb

# Put other settings into a local configuration file.
cat > /etc/dspam/dspam.d/local.conf << EOF;
IgnoreHeader X-Spam-Status
IgnoreHeader X-Spam-Scanned
IgnoreHeader X-Virus-Scanner-Result
IgnoreHeader X-Virus-Scanned
IgnoreHeader X-DKIM
IgnoreHeader DKIM-Signature
IgnoreHeader DomainKey-Signature
IgnoreHeader X-Google-Dkim-Signature
EOF

# Global preferences.
tools/editconf.py /etc/dspam/default.prefs \
	spamAction=deliver \
	signatureLocation=headers \
	showFactors=on

# Hook into postfix. Replace dovecot with dspam as the mail delivery agent.
# dspam is configured above to pass mail on to dovecot next.
tools/editconf.py /etc/postfix/main.cf virtual_transport=lmtp:[127.0.0.1]:2424

# Hook into dovecot... these aren't tested.

# Automatically move spam into a folder called Spam. Enable the sieve plugin.
# (Note: Be careful if we want to use multiple plugins later.)
sudo sed -i "s/#mail_plugins = .*/mail_plugins = \$mail_plugins sieve/" /etc/dovecot/conf.d/20-lmtp.conf

# The sieve scripts are installed by users_update.sh.

# to detect when a message moves between folders so we can
# pass it to dspam for training. (Be careful if we use multiple plugins later.)
# This is not finished.
sudo sed -i "s/#mail_plugins = .*/mail_plugins = \$mail_plugins antispam/" /etc/dovecot/conf.d/20-imap.conf
	
# Create storage space.
mkdir -p $STORAGE_ROOT/mail/dspam
chown dspam:dspam $STORAGE_ROOT/mail/dspam

service dspam restart
service postfix restart

