#!/bin/bash
# clamsmtpd virus scanning
# ----------------------

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

echo "Installing clamsmtpd (ClamAV e-mail virus scanning)..."


# Install clamav-daemon & clamsmtpd with additional scanning formats
apt_install sqlite clamav-daemon clamav clamsmtp unzip p7zip zip arj bzip2 cabextract cpio file gzip lhasa nomarch pax rar unrar unzip zip zoo


# Config /etc/clamsmtpd.conf
# Config edits do the following:
# Default port of 10025 is already in use by <>, using unused port 10028 to pass back from clamsmtpd to postfix.
# Default port of 10026 for listening from postfix is already in use by <>, using unused port 10027 instead.
# Add X-AV-Checked Header
# Adds script to notify destination user only (since sender may be spoofed) that mail was dropped due to virus detection)

tools/editconf.py /etc/clamsmtpd.conf -s \
                OutAddress:=127.0.0.1:10028 \
                Listen:=127.0.0.1:10027 \
                Header:="X-AV-Checked: ClamAV" \
                VirusAction:="/usr/local/lib/clamsmtpd/email_virus_notify.sh"

# Configure postfix main.cf

tools/editconf.py /etc/postfix/main.cf \
content_filter=scan:127.0.0.1:10027 #\
#not sure if the below is needed/wanted, RFC - http://www.postfix.org/postconf.5.html#receive_override_options
#receive_override_options=no_address_mappings

# Configure postfix master.cf
tools/editconf.py /etc/postfix/master.cf -s -w \
        "scan=unix  -       -       n       -       16      smtp
          -o smtp_send_xforward_command=yes" \
        "127.0.0.1:10028=inet  n -       n       -       16      smtpd
          -o content_filter=
          -o receive_override_options=no_unknown_recipient_checks,no_header_body_checks
          -o smtpd_helo_restrictions=
          -o smtpd_client_restrictions=
          -o smtpd_sender_restrictions=
          -o smtpd_recipient_restrictions=permit_mynetworks,reject
          -o mynetworks_style=host
          -o smtpd_authorized_xforward_hosts=127.0.0.0/8"

# Config Notification Script
# Inspiration from https://h4des.org/blog/index.php?/archives/308-clamsmtp-informing-recipients-abount-email-virus-infection.html
mkdir -p /usr/local/lib/clamsmtpd
chown clamsmtp:clamsmtp /usr/local/lib/clamsmtpd
cp tools/email_virus_notify.sh /usr/local/lib/clamsmtpd/email_virus_notify.sh
chown clamsmtp:clamsmtp /usr/local/lib/clamsmtpd/email_virus_notify.sh
chmod 700 /usr/local/lib/clamsmtpd/email_virus_notify.sh

# Force virus def updates
echo "Updating ClamAV Definitions"
echo ""
/usr/bin/freshclam


# restart postfix, start clamsmtpd, clamav-daemon, clamav-freshclam
adduser clamsmtp clamav > /dev/null
restart_service postfix
restart_service clamsmtp
restart_service clamav-daemon
restart_service clamav-freshclam
