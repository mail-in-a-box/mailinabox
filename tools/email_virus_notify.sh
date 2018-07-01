#!/bin/bash
#
# This script will notify users that email was dropped by clamsmtpd.
#
# Original inspiration from this script: https://h4des.org/blog/index.php?/archives/308-clamsmtp-informing-recipients-abount-email-virus-infection.html

source /etc/mailinabox.conf # load global vars
# For all variables passed when running this script please see "man clamsmtpd.conf"

#pull list of all emails served by this mailserver
dest_email=$(/usr/bin/sqlite3 /home/user-data/mail/users.sqlite "select distinct source from aliases union all select distinct email from users;")

# check every single recipient
for i in $RECIPIENTS; do

# check every single email/alias
for j in $dest_email; do

#check if email address contains hosted domain name
# $i contains email address
# $j contains hosted email
if [[ "$i" == "$j" ]]
then
{
echo "Subject: Email Virus Scan Notification"
echo ""
echo "Hello $i,"
echo ""
echo "This is the email system of $PRIMARY_HOSTNAME."
echo ""
echo "The email from $SENDER to you was infected with a virus ($VIRUS)."
echo "The email was blocked and this notification was sent instead."
echo ""
echo "If you encounter further problems please contact your System Administrator."
echo ""
echo "Regards,"
echo "The email server at $PRIMARY_HOSTNAME"
#sending email to recipient that is hosted on this system
} | sendmail -f "postmaster@$PRIMARY_HOSTNAME" "$i"
#continue with next recipient

fi

done

done
