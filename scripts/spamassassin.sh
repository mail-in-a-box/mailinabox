# Spam filtering with spamassassin via spampd.

apt-get -q -y install spampd dovecot-antispam

# Hook into postfix. Replace dovecot with spampd as the mail delivery agent.
tools/editconf.py /etc/postfix/main.cf virtual_transport=lmtp:[127.0.0.1]:10025

# Hook into dovecot. This is actually the default but we don't want to lose track of it.
tools/editconf.py /etc/default/spampd DESTPORT=10026

# Automatically move spam into a folder called Spam. Enable the sieve plugin.
# (Note: Be careful if we want to use multiple plugins later.)
# The sieve scripts are installed by users_update.sh.
sudo sed -i "s/#mail_plugins = .*/mail_plugins = \$mail_plugins sieve/" /etc/dovecot/conf.d/20-lmtp.conf

# Enable the antispam plugin to detect when a message moves between folders so we can
# pass it to sa-learn for training. (Be careful if we use multiple plugins later.)
sudo sed -i "s/#mail_plugins = .*/mail_plugins = \$mail_plugins antispam/" /etc/dovecot/conf.d/20-imap.conf

# When mail is moved in or out of the dovecot Spam folder, re-train.
# from http://wiki2.dovecot.org/Plugins/Antispam
cat > /usr/bin/sa-learn-pipe.sh << EOF;
cat<&0 >> /tmp/sendmail-msg-\$\$.txt
/usr/bin/sa-learn \$* /tmp/sendmail-msg-\$\$.txt > /dev/null
rm -f /tmp/sendmail-msg-\$\$.txt
exit 0
EOF

chmod a+x /usr/bin/sa-learn-pipe.sh

cat > /etc/dovecot/conf.d/99-local-spampd.conf << EOF;
plugin {
    antispam_backend = pipe
    antispam_spam_pattern_ignorecase = SPAM
    antispam_allow_append_to_spam = yes
    antispam_pipe_program_spam_arg = /usr/bin/sa-learn-pipe.sh --spam
    antispam_pipe_program_notspam_arg = /usr/bin/sa-learn-pipe.sh --ham
    antispam_pipe_program = /bin/bash
}
EOF

# Initial training?
# sa-learn --ham storage/mail/mailboxes/*/*/cur/
# sa-learn --spam storage/mail/mailboxes/*/*/.Spam/cur/

sudo service spampd restart
sudo service dovecot restart

