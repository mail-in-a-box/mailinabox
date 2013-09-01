# Spam filtering with spamassassin via spampd
#############################################

# spampd sits between postfix and dovecot. It takes mail from postfix
# over the LMTP protocol, runs spamassassin on it, and then passes the
# message over LMTP to dovecot for local delivery.

# In order to move spam automatically into the Spam folder we use the dovecot sieve
# plugin. Unfortunately, each mail box needs its own sieve script set to do the
# filtering work. So users_update.sh must be run any time a new mail user is created.

# Install packages.
apt-get -q -y install spampd dovecot-sieve dovecot-antispam

# Hook into postfix. Replace dovecot with spampd as the mail delivery agent.
tools/editconf.py /etc/postfix/main.cf virtual_transport=lmtp:[127.0.0.1]:10025

# Pass messages on to docevot on port 10026.
# This is actually the default setting but we don't want to lose track of it.
tools/editconf.py /etc/default/spampd DESTPORT=10026

# Enable the sieve plugin which let's us set a script that automatically moves
# spam into the user's Spam mail filter.
# (Note: Be careful if we want to use multiple plugins later.)
sudo sed -i "s/#mail_plugins = .*/mail_plugins = \$mail_plugins sieve/" /etc/dovecot/conf.d/20-lmtp.conf

# Enable the antispam plugin to detect when a message moves between folders so we can
# pass it to sa-learn for training. (Be careful if we use multiple plugins later.)
sudo sed -i "s/#mail_plugins = .*/mail_plugins = \$mail_plugins antispam/" /etc/dovecot/conf.d/20-imap.conf

# When mail is moved in or out of the dovecot Spam folder, re-train using this script
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

