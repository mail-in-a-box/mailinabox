#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

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

sudo -u www-data php$PHP_VER /usr/local/lib/owncloud/occ group:adduser admin $ADMIN && echo Done.
