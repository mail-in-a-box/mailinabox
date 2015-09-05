#!/bin/bash
# Spam filtering with spamassassin via spampd
# -------------------------------------------
#
# spampd sits between postfix and dovecot. It takes mail from postfix
# over the LMTP protocol, runs spamassassin on it, and then passes the
# message over LMTP to dovecot for local delivery.
#
# In order to move spam automatically into the Spam folder we use the dovecot sieve
# plugin.

source /etc/mailinabox.conf # get global vars
source setup/functions.sh # load our functions

# Install packages and basic configuration
# ----------------------------------------

# Install packages.
# libmail-dkim-perl is needed to make the spamassassin DKIM module work.
# For more information see Debian Bug #689414:
# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=689414
echo "Installing SpamAssassin..."
apt_install spampd razor pyzor dovecot-antispam libmail-dkim-perl

# Allow spamassassin to download new rules.
tools/editconf.py /etc/default/spamassassin \
	CRON=1

# Configure pyzor, which is a client to a live database of hashes of
# spam emails. Set the pyzor configuration directory to something sane.
# The default is ~/.pyzor. We used to use that, so we'll kill that old
# directory. Then write the public pyzor server to its servers file.
# That will prevent an automatic download on first use, and also means
# we can skip 'pyzor discover', both of which are currently broken by
# something happening on Sourceforge (#496).
rm -rf ~/.pyzor
tools/editconf.py /etc/spamassassin/local.cf -s \
	pyzor_options="--homedir /etc/spamassassin/pyzor"
mkdir -p /etc/spamassassin/pyzor
echo "public.pyzor.org:24441" > /etc/spamassassin/pyzor/servers
# check with: pyzor --homedir /etc/mail/spamassassin/pyzor ping

# Configure spampd:
# * Pass messages on to docevot on port 10026. This is actually the default setting but we don't
#   want to lose track of it. (We've configured Dovecot to listen on this port elsewhere.)
# * Increase the maximum message size of scanned messages from the default of 64KB to 500KB, which
#   is Spamassassin (spamc)'s own default. Specified in KBytes.
# * Disable localmode so Pyzor, DKIM and DNS checks can be used.
tools/editconf.py /etc/default/spampd \
	DESTPORT=10026 \
	ADDOPTS="\"--maxsize=500\"" \
	LOCALONLY=0

# Spamassassin normally wraps spam as an attachment inside a fresh
# email with a report about the message. This also protects the user
# from accidentally openening a message with embedded malware.
#
# It's nice to see what rules caused the message to be marked as spam,
# but it's also annoying to get to the original message when it is an
# attachment, modern mail clients are safer now and don't load remote
# content or execute scripts, and it is probably confusing to most users.
#
# Tell Spamassassin not to modify the original message except for adding
# the X-Spam-Status mail header and related headers.
tools/editconf.py /etc/spamassassin/local.cf -s \
	report_safe=0

# Bayesean learning
# -----------------
#
# Spamassassin can learn from mail marked as spam or ham, but it needs to be
# configured. We'll store the learning data in our storage area.
#
# These files must be:
#
# * Writable by sa-learn-pipe script below, which run as the 'mail' user, for manual tagging of mail as spam/ham.
# * Readable by the spampd process ('spampd' user) during mail filtering.
# * Writable by the debian-spamd user, which runs /etc/cron.daily/spamassassin.
#
# We'll have these files owned by spampd and grant access to the other two processes.

tools/editconf.py /etc/spamassassin/local.cf -s \
	bayes_path=$STORAGE_ROOT/mail/spamassassin/bayes

mkdir -p $STORAGE_ROOT/mail/spamassassin
chown -R spampd:spampd $STORAGE_ROOT/mail/spamassassin

# To mark mail as spam or ham, just drag it in or out of the Spam folder. We'll
# use the Dovecot antispam plugin to detect the message move operation and execute
# a shell script that invokes learning.

# Enable the Dovecot antispam plugin.
# (Be careful if we use multiple plugins later.) #NODOC
sed -i "s/#mail_plugins = .*/mail_plugins = \$mail_plugins antispam/" /etc/dovecot/conf.d/20-imap.conf
sed -i "s/#mail_plugins = .*/mail_plugins = \$mail_plugins antispam/" /etc/dovecot/conf.d/20-pop3.conf

# Configure the antispam plugin to call sa-learn-pipe.sh.
cat > /etc/dovecot/conf.d/99-local-spampd.conf << EOF;
plugin {
    antispam_backend = pipe
    antispam_spam_pattern_ignorecase = SPAM
    antispam_trash_pattern_ignorecase = trash;Deleted *
    antispam_allow_append_to_spam = yes
    antispam_pipe_program_spam_args = /usr/local/bin/sa-learn-pipe.sh;--spam
    antispam_pipe_program_notspam_args = /usr/local/bin/sa-learn-pipe.sh;--ham
    antispam_pipe_program = /bin/bash
}
EOF

# Have Dovecot run its mail process with a supplementary group (the spampd group)
# so that it can access the learning files.

tools/editconf.py /etc/dovecot/conf.d/10-mail.conf \
	mail_access_groups=spampd

# Here's the script that the antispam plugin executes. It spools the message into
# a temporary file and then runs sa-learn on it.
# from http://wiki2.dovecot.org/Plugins/Antispam
rm -f /usr/bin/sa-learn-pipe.sh # legacy location #NODOC
cat > /usr/local/bin/sa-learn-pipe.sh << EOF;
cat<&0 >> /tmp/sendmail-msg-\$\$.txt
/usr/bin/sa-learn \$* /tmp/sendmail-msg-\$\$.txt > /dev/null
rm -f /tmp/sendmail-msg-\$\$.txt
exit 0
EOF
chmod a+x /usr/local/bin/sa-learn-pipe.sh

# Create empty bayes training data (if it doesn't exist). Once the files exist,
# ensure they are group-writable so that the Dovecot process has access.
sudo -u spampd /usr/bin/sa-learn --sync 2>/dev/null
chmod -R 660 $STORAGE_ROOT/mail/spamassassin
chmod 770 $STORAGE_ROOT/mail/spamassassin

# Initial training?
# sa-learn --ham storage/mail/mailboxes/*/*/cur/
# sa-learn --spam storage/mail/mailboxes/*/*/.Spam/cur/

# Kick services.
restart_service spampd
restart_service dovecot

