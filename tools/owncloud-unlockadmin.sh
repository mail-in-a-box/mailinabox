#!/bin/bash
#
# This script will give you administrative access to the Nextcloud
# instance running here.
#
# Run this at your own risk. This is for testing & experimentation
# purpopses only. After this point you are on your own.

source /etc/mailinabox.conf # load global vars

ADMIN=$(./mail.py user admins | head -n 1)
test -z "$1" || ADMIN=$1 

echo I am going to unlock admin features for $ADMIN.
echo You can provide another user to unlock as the first argument of this script.
echo
echo WARNING: you could break mail-in-a-box when fiddling around with Nextcloud\'s admin interface
echo If in doubt, press CTRL-C to cancel.
echo 
echo Press enter to continue.
read

sudo -u www-data php /usr/local/lib/owncloud/occ group:adduser admin $ADMIN && echo Done.
