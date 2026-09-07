#!/bin/bash
#
# Dovecot (IMAP/POP and LDA)
# ----------------------
#
# Dovecot is *both* the IMAP/POP server (the protocol that email applications
# use to query a mailbox) as well as the local delivery agent (LDA),
# meaning it is responsible for writing emails to mailbox storage on disk.
# You could imagine why these things would be bundled together.
#
# As part of local mail delivery, Dovecot executes actions on incoming
# mail as defined in a "sieve" script.
#
# Dovecot's LDA role comes after spam filtering. Postfix hands mail off
# to Spamassassin which in turn hands it off to Dovecot. This all happens
# using the LMTP protocol.

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars


# Install packages for dovecot. These are all core dovecot plugins,
# but dovecot-lucene is packaged by *us* in the Mail-in-a-Box PPA,
# not by Ubuntu.

echo "Installing Dovecot (IMAP server)..."
apt_install \
	dovecot-core dovecot-imapd dovecot-pop3d dovecot-lmtpd dovecot-sqlite sqlite3 \
	dovecot-sieve dovecot-managesieved

# The `dovecot-imapd`, `dovecot-pop3d`, and `dovecot-lmtpd` packages automatically
# enable IMAP, POP and LMTP protocols.

# Set basic daemon options.

## The 'default_client_limit' is 1000, which is lower than required, if
# all of our services reach their maximum, currently:
# service imap-urlauth-login { process_limit=250 }
# service imap-login { process_limit=250 }
# service pop3-login { process_limit=250 }
# service lmtp { process_limit=250 }
# service managesieve-login { process_limit=250 }
# So we set it to our mimumum, 1250.
## The `default_process_limit` is 100, which constrains the total number
# of active IMAP connections (at, say, 5 open connections per user that
# would be 20 users). Set it to 250 times the number of cores this
# machine has, so on a two-core machine that's 500 processes/100 users).
## The `default_vsz_limit` is the maximum amount of virtual memory that
# can be allocated. It should be set *reasonably high* to avoid allocation
# issues with larger mailboxes. We're setting it to 1/3 of the total
# available memory (physical mem + swap) to be sure.
# See here for discussion:
# - https://www.dovecot.org/list/dovecot/2012-August/137569.html
# - https://www.dovecot.org/list/dovecot/2011-December/132455.html
tools/editconf.py /etc/dovecot/conf.d/10-master.conf \
    default_client_limit="$(($(nproc) * 1250))" \
	default_process_limit="$(($(nproc) * 250))" \
	default_vsz_limit="$(($(free -tm  | tail -1 | awk '{print $2}') / 3))M" \
	log_path=/var/log/mail.log

# The inotify `max_user_instances` default is 128, which constrains
# the total number of watched (IMAP IDLE push) folders by open connections.
# See http://www.dovecot.org/pipermail/dovecot/2013-March/088834.html.
# A reboot is required for this to take effect (which we don't do as
# as a part of setup). Test with `cat /proc/sys/fs/inotify/max_user_instances`.
# We changed where this writes to
tools/editconf.py /usr/lib/sysctl.d/50-default.conf \
	fs.inotify.max_user_instances=1024

# Restart sysctl, then apply the change to the system
hide_output systemctl restart systemd-sysctl
hide_output sysctl --system


# Copy in preconfigured dovecot configuration files
cp -f conf/dovecot-10-mail.conf /etc/dovecot/conf.d/10-mail.conf
cp -f conf/dovecot-mailboxes.conf /etc/dovecot/conf.d/15-mailboxes.conf
cp -f conf/dovecot-20-imap.conf /etc/dovecot/conf.d/20-imap.conf
cp -f conf/dovecot-20-pop3.conf /etc/dovecot/conf.d/20-pop3.conf
cp -f conf/dovecot-20-lmtp.conf /etc/dovecot/conf.d/20-lmtp.conf
cp -f conf/dovecot-90-quota.conf /etc/dovecot/conf.d/90-quota.conf
cp -f conf/dovecot-99-local-sieve.conf /etc/dovecot/conf.d/99-local-sieve.conf

# Set the location where we'll store user mailboxes. '%{user|domain}' is the domain name and '%{user|username}' is the
# username part of the user's email address. We'll ensure that no bad domains or email addresses
# are created within the management daemon.
tools/editconf.py /etc/dovecot/conf.d/10-mail.conf \
    mail_path="$STORAGE_ROOT/mail/mailboxes/%{user|domain}/%{user|username}"

# ### IMAP/POP

# Require that passwords are sent over SSL only, and allow the usual IMAP authentication mechanisms.
# The LOGIN mechanism is supposedly for Microsoft products like Outlook to do SMTP login (I guess
# since we're using Dovecot to handle SMTP authentication?).
tools/editconf.py /etc/dovecot/conf.d/10-auth.conf \
	auth_allow_cleartext=no \
	"auth_mechanisms=plain login"

# Enable SSL, specify the location of the SSL certificate and private key files.
# Use Mozilla's "Intermediate" recommendations at https://ssl-config.mozilla.org/#server=dovecot&server-version=2.2.33&config=intermediate&openssl-version=1.1.1,
# except that the current version of Dovecot does not have a TLSv1.3 setting, so we only use TLSv1.2.
tools/editconf.py /etc/dovecot/conf.d/10-ssl.conf \
	"ssl = required" \
	"ssl_server_cert_file = $STORAGE_ROOT/ssl/ssl_certificate.pem" \
	"ssl_server_key_file = $STORAGE_ROOT/ssl/ssl_private_key.pem" \
	"ssl_cipher_list = ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384" \
	"ssl_server_prefer_ciphers = client" \
	"ssl_server_dh_file = $STORAGE_ROOT/ssl/dh4096.pem"

# Disable in-the-clear IMAP/POP because there is no reason for a user to transmit
# login credentials outside of an encrypted connection. Only the over-TLS versions
# are made available (IMAPS on port 993; POP3S on port 995).
sed -i "s/#port = 143/port = 0/" /etc/dovecot/conf.d/10-master.conf
sed -i "s/#port = 110/port = 0/" /etc/dovecot/conf.d/10-master.conf

# ### LDA (LMTP)

# Enable Dovecot's LDA service with the LMTP protocol. It will listen
# on port 10026, and Spamassassin will be configured to pass mail there.
#
# The disabled unix socket listener is normally how Postfix and Dovecot
# would communicate (see the Postfix setup script for the corresponding
# setting also commented out).
#
cat > /etc/dovecot/conf.d/99-local.conf << EOF;
service lmtp {
  inet_listener lmtp {
    listen = 127.0.0.1
    port = 10026
  }
}

# Enable imap-login on localhost to allow the user_external plugin
# for Nextcloud to do imap authentication. (See #1577)
service imap-login {
  inet_listener imap {
    listen = 127.0.0.1
    port = 143
  }
}
EOF

# Setting a `postmaster_address` is required or LMTP won't start. An alias
# will be created automatically by our management daemon.
tools/editconf.py /etc/dovecot/conf.d/15-lda.conf \
	"postmaster_address=postmaster@$PRIMARY_HOSTNAME"

# Copy the global sieve script into where we've told Dovecot to look for it. Then
# compile it. Global scripts must be compiled now because Dovecot won't have
# permission later.
cp conf/sieve-spam.txt /etc/dovecot/sieve-spam.sieve
sievec /etc/dovecot/sieve-spam.sieve

# PERMISSIONS

# Ensure configuration files are owned by dovecot and not world readable.
chown -R mail:dovecot /etc/dovecot
chmod -R o-rwx /etc/dovecot

# Ensure mailbox files have a directory that exists and are owned by the mail user.
mkdir -p "$STORAGE_ROOT/mail/mailboxes"
chown -R mail:mail "$STORAGE_ROOT/mail/mailboxes"

# Same for the sieve scripts.
mkdir -p "$STORAGE_ROOT/mail/sieve"
mkdir -p "$STORAGE_ROOT/mail/sieve/global_before"
mkdir -p "$STORAGE_ROOT/mail/sieve/global_after"
chown -R mail:mail "$STORAGE_ROOT/mail/sieve"

# Allow the IMAP/POP ports in the firewall.
ufw_allow imaps
ufw_allow pop3s

# Allow the Sieve port in the firewall.
ufw_allow sieve

# Restart services.
restart_service dovecot
