#!/bin/bash
# Spam filtering with spamassassin via spampd
# ===========================================
#
# spampd sits between postfix and dovecot. It takes mail from postfix
# over the LMTP protocol, runs spamassassin on it, and then passes the
# message over LMTP to dovecot for local delivery.
#
# In order to move spam automatically into the Spam folder we use the dovecot sieve
# plugin.

source /etc/mailinabox.conf # get global vars
source setup/functions.sh # load our functions

# Install packages.
apt_install spampd razor pyzor dovecot-antispam

# Allow spamassassin to download new rules.
tools/editconf.py /etc/default/spamassassin \
	CRON=1

# Configure pyzor.
hide_output pyzor discover

# Pass messages on to docevot on port 10026.
# This is actually the default setting but we don't want to lose track of it.
# We've already configured Dovecot to listen on this port.
tools/editconf.py /etc/default/spampd DESTPORT=10026

# Enable the Dovecot antispam plugin to detect when a message moves between folders so we can
# pass it to sa-learn for training.
# (Be careful if we use multiple plugins later.) #NODOC
sed -i "s/#mail_plugins = .*/mail_plugins = \$mail_plugins antispam/" /etc/dovecot/conf.d/20-imap.conf

# When mail is moved in or out of the Dovecot Spam folder, re-train using this script
# that sends the mail to spamassassin.
# from http://wiki2.dovecot.org/Plugins/Antispam
rm -f /usr/bin/sa-learn-pipe.sh # legacy location #NODOC
cat > /usr/local/bin/sa-learn-pipe.sh << EOF;
cat<&0 >> /tmp/sendmail-msg-\$\$.txt
/usr/bin/sa-learn \$* /tmp/sendmail-msg-\$\$.txt > /dev/null
rm -f /tmp/sendmail-msg-\$\$.txt
exit 0
EOF
chmod a+x /usr/local/bin/sa-learn-pipe.sh

# Configure the antispam plugin to call sa-learn-pipe.sh.
cat > /etc/dovecot/conf.d/99-local-spampd.conf << EOF;
plugin {
    antispam_backend = pipe
    antispam_spam_pattern_ignorecase = SPAM
    antispam_allow_append_to_spam = yes
    antispam_pipe_program_spam_args = /usr/local/bin/sa-learn-pipe.sh;--spam
    antispam_pipe_program_notspam_args = /usr/local/bin/sa-learn-pipe.sh;--ham
    antispam_pipe_program = /bin/bash
}
EOF

# Configure site-wide bayesean learning. These files must be:
#
# * Writable by the sa-learn-pipe script which run as the 'mail' user, for manual tagging of mail as spam/ham.
# * Readable by the spampd process ('spampd' user) during mail filtering.
# * Writable by the debian-spamd user, which runs /etc/cron.daily/spamassassin.
#
# We'll have these files owned by spampd and grant access to the other two processes.

# Create the storage space owned by spampd.
mkdir -p $STORAGE_ROOT/mail/spamassassin
chown -R spampd:spampd $STORAGE_ROOT/mail/spamassassin
chmod -R 775 $STORAGE_ROOT/mail/spamassassin

# Create empty bayes training data (if it doesn't exist) owned by spampd.
sudo -u spampd /usr/bin/sa-learn --sync 2>/dev/null

# Have dovecot execute the antispam script (and other mail processes) in the spampd group
# (as a supplementary group) so that it can read/write these files.
tools/editconf.py /etc/dovecot/conf.d/10-mail.conf \
	mail_access_groups=spampd

# Tell spamassassin where the file is.
tools/editconf.py /etc/spamassassin/local.cf -s \
	bayes_path=$STORAGE_ROOT/mail/spamassassin/bayes

# Initial training?
# sa-learn --ham storage/mail/mailboxes/*/*/cur/
# sa-learn --spam storage/mail/mailboxes/*/*/.Spam/cur/

# Kick services.
restart_service spampd
restart_service dovecot

