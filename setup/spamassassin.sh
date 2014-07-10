# Spam filtering with spamassassin via spampd
#############################################

# spampd sits between postfix and dovecot. It takes mail from postfix
# over the LMTP protocol, runs spamassassin on it, and then passes the
# message over LMTP to dovecot for local delivery.

# In order to move spam automatically into the Spam folder we use the dovecot sieve
# plugin. The tools/mail.py tool creates the necessary sieve script for each mail
# user when the mail user is created.

source setup/functions.sh # load our functions

# Install packages.
apt_install spampd razor pyzor dovecot-antispam

# Allow spamassassin to download new rules.
tools/editconf.py /etc/default/spamassassin \
	CRON=1

# Configure pyzor.
pyzor discover

# Pass messages on to docevot on port 10026.
# This is actually the default setting but we don't want to lose track of it.
# We've already configured Dovecot to listen on this port.
tools/editconf.py /etc/default/spampd DESTPORT=10026

# Enable the Dovecot antispam plugin to detect when a message moves between folders so we can
# pass it to sa-learn for training. (Be careful if we use multiple plugins later.)
sudo sed -i "s/#mail_plugins = .*/mail_plugins = \$mail_plugins antispam/" /etc/dovecot/conf.d/20-imap.conf

# When mail is moved in or out of the Dovecot Spam folder, re-train using this script
# that sends the mail to spamassassin.
# from http://wiki2.dovecot.org/Plugins/Antispam
cat > /usr/bin/sa-learn-pipe.sh << EOF;
cat<&0 >> /tmp/sendmail-msg-\$\$.txt
/usr/bin/sa-learn \$* /tmp/sendmail-msg-\$\$.txt > /dev/null
rm -f /tmp/sendmail-msg-\$\$.txt
exit 0
EOF
chmod a+x /usr/bin/sa-learn-pipe.sh

# Configure the antispam plugin to call sa-learn-pipe.sh.
cat > /etc/dovecot/conf.d/99-local-spampd.conf << EOF;
plugin {
    antispam_backend = pipe
    antispam_spam_pattern_ignorecase = SPAM
    antispam_allow_append_to_spam = yes
    antispam_pipe_program_spam_args = /usr/bin/sa-learn-pipe.sh;--spam
    antispam_pipe_program_notspam_args = /usr/bin/sa-learn-pipe.sh;--ham
    antispam_pipe_program = /bin/bash
}
EOF

# Initial training?
# sa-learn --ham storage/mail/mailboxes/*/*/cur/
# sa-learn --spam storage/mail/mailboxes/*/*/.Spam/cur/

# Kick services.
sudo service spampd restart
sudo service dovecot restart

