#!/bin/bash
#
# Dovecot (IMAP and LDA)
#
# Dovecot is *both* the IMAP server (the protocol that email applications
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

# Install packages.

apt_install \
	dovecot-core dovecot-imapd dovecot-lmtpd dovecot-sqlite sqlite3 \
	dovecot-sieve dovecot-managesieved

# The dovecot-imapd dovecot-lmtpd packages automatically enable IMAP and LMTP protocols.

# Set the location where we'll store user mailboxes.
tools/editconf.py /etc/dovecot/conf.d/10-mail.conf \
	mail_location=maildir:$STORAGE_ROOT/mail/mailboxes/%d/%n \
	mail_privileged_group=mail \
	first_valid_uid=0

# IMAP

# Require that passwords are sent over SSL only, and allow the usual IMAP authentication mechanisms.
# The LOGIN mechanism is supposedly for Microsoft products like Outlook to do SMTP login (I guess
# since we're using Dovecot to handle SMTP authentication?).
tools/editconf.py /etc/dovecot/conf.d/10-auth.conf \
	disable_plaintext_auth=yes \
	"auth_mechanisms=plain login"

# Enable SSL, specify the location of the SSL certificate and private key files,
# and allow only good ciphers per http://baldric.net/2013/12/07/tls-ciphers-in-postfix-and-dovecot/.
tools/editconf.py /etc/dovecot/conf.d/10-ssl.conf \
	ssl=required \
	"ssl_cert=<$STORAGE_ROOT/ssl/ssl_certificate.pem" \
	"ssl_key=<$STORAGE_ROOT/ssl/ssl_private_key.pem" \
	"ssl_cipher_list=TLSv1+HIGH !SSLv2 !RC4 !aNULL !eNULL !3DES @STRENGTH"

# Disable in-the-clear IMAP and POP because we're paranoid (we haven't even
# enabled POP).
sed -i "s/#port = 143/port = 0/" /etc/dovecot/conf.d/10-master.conf
sed -i "s/#port = 110/port = 0/" /etc/dovecot/conf.d/10-master.conf

# Make IMAP IDLE slightly more efficient. By default, Dovecot says "still here"
# every two minutes. With K-9 mail, the bandwidth and battery usage due to
# this are minimal. But for good measure, let's go to 4 minutes to halve the
# bandwidth and number of times the device's networking might be woken up.
# The risk is that if the connection is silent for too long it might be reset
# by a peer. See #129 and http://razor.occams.info/blog/2014/08/09/how-bad-is-imap-idle/.
tools/editconf.py /etc/dovecot/conf.d/20-imap.conf \
	imap_idle_notify_interval="4 mins"

# LDA (LMTP)

# Enable Dovecot's LDA service with the LMTP protocol. It will listen
# in port 10026, and Spamassassin will be configured to pass mail there.
#
# The disabled unix socket listener is normally how Postfix and Dovecot
# would communicate (see the Postfix setup script for the corresponding
# setting also commented out).
#
# Also increase the number of allowed IMAP connections per mailbox because
# we all have so many devices lately.
cat > /etc/dovecot/conf.d/99-local.conf << EOF;
service lmtp {
  #unix_listener /var/spool/postfix/private/dovecot-lmtp {
  #  user = postfix
  #  group = postfix
  #}
  inet_listener lmtp {
    address = 127.0.0.1
    port = 10026
  }
}

protocol imap {
  mail_max_userip_connections = 20
}
EOF

# Setting a postmaster_address seems to be required or LMTP won't start.
tools/editconf.py /etc/dovecot/conf.d/15-lda.conf \
	postmaster_address=postmaster@$PRIMARY_HOSTNAME

# SIEVE

# Enable the Dovecot sieve plugin which let's users run scripts that process
# mail as it comes in. We'll also set a global script that moves mail marked
# as spam by Spamassassin into the user's Spam folder.
sudo sed -i "s/#mail_plugins = .*/mail_plugins = \$mail_plugins sieve/" /etc/dovecot/conf.d/20-lmtp.conf

cat > /etc/dovecot/conf.d/99-local-sieve.conf << EOF;
plugin {
  # The path to our global sieve which handles moving spam to the Spam folder.
  sieve_before = /etc/dovecot/sieve-spam.sieve

  # The path to the user's main active script. ManageSieve will create a symbolic
  # link here to the actual sieve script. It should not be in the mailbox directory
  # (because then it might appear as a folder) and it should not be in the sieve_dir
  # (because then I suppose it might appear to the user as one of their scripts).
  sieve = $STORAGE_ROOT/mail/sieve/%d/%n.sieve

  # Directory for :personal include scripts for the include extension. This
  # is also where the ManageSieve service stores the user's scripts.
  sieve_dir = $STORAGE_ROOT/mail/sieve/%d/%n
}
EOF

# Copy the global sieve script into where we've told Dovecot to look for it. Then
# compile it. Global scripts must be compiled now because Dovecot won't have
# permission later.
cp `pwd`/conf/sieve-spam.txt /etc/dovecot/sieve-spam.sieve
sievec /etc/dovecot/sieve-spam.sieve

# PERMISSIONS

# Ensure configuration files are owned by dovecot and not world readable.
chown -R mail:dovecot /etc/dovecot
chmod -R o-rwx /etc/dovecot

# Ensure mailbox files have a directory that exists and are owned by the mail user.
mkdir -p $STORAGE_ROOT/mail/mailboxes
chown -R mail.mail $STORAGE_ROOT/mail/mailboxes

# Same for the sieve scripts.
mkdir -p $STORAGE_ROOT/mail/sieve
chown -R mail.mail $STORAGE_ROOT/mail/sieve

# Allow the IMAP port in the firewall.
ufw_allow imaps

# Restart services.
restart_service dovecot
