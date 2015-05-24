#!/bin/bash
# CardDAV client/sync for RoundCube Mail
##########################

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# initialize roundcube database
export PRIVATE_IP
curl -sk https://${PRIVATE_IP}/mail/index.php 2>&1 >> /tmp/roundcube_db_init.log

# Work around bug in db init code in rcmcarddav
RCMSQLF=/home/user-data/mail/roundcube/roundcube.sqlite
DBINIT=/usr/local/lib/roundcubemail/plugins/carddav/dbinit/sqlite3.sql
DBMIG=/usr/local/lib/roundcubemail/plugins/carddav/dbmigrations/0000-dbinit/sqlite3.sql

# This may fail if we've already created the database, so capture output
/usr/bin/sqlite3 $RCMSQLF < $DBINIT &> /tmp/dbinit.log

