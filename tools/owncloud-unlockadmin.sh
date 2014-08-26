#!/bin/bash

source /etc/mailinabox.conf # load global vars

ADMIN=$(sqlite3 $STORAGE_ROOT/mail/users.sqlite "SELECT email FROM users WHERE privileges = 'admin' ORDER BY id ASC LIMIT 1")
test -z "$1" || ADMIN=$1 

echo I am going to unlock admin features for $ADMIN.
echo You can provide another user to unlock as the first argument of this script.
echo 
echo WARNING: you could break mail-in-a-box when fiddling around with owncloud\'s admin interface
echo If in doubt, press CTRL-C to cancel.
echo 
echo Press enter to continue.
read

sqlite3 $STORAGE_ROOT/owncloud/owncloud.db "INSERT OR IGNORE INTO oc_group_user VALUES ('admin', '$ADMIN')" && echo Done.
