#!/bin/bash
#
# This script will restore the backup made during an installation
source /etc/mailinabox.conf # load global vars

if [ -z "$1" ]; then
	echo "Usage: owncloud-restore.sh <backup directory>"
	echo
	echo "WARNING: This will restore the database to the point of the installation!"
	echo "         This means that you will lose all changes made by users after that point"
	echo
	echo
	echo "Backups are stored here: $STORAGE_ROOT/owncloud-backup/"
	echo
	echo "Available backups:"
	echo
	find $STORAGE_ROOT/owncloud-backup/* -maxdepth 0 -type d
	echo
	echo "Supply the directory that was created during the last installation as the only commandline argument"
	exit
fi

if [ ! -f $1/config.php ]; then
	echo "This isn't a valid backup location"
	exit 1
fi

echo "Restoring backup from $1"
service php8.2-fpm stop

# remove the current ownCloud/Nextcloud installation
rm -rf /usr/local/lib/owncloud/
# restore the current ownCloud/Nextcloud application
cp -r  "$1/owncloud-install" /usr/local/lib/owncloud

# restore access rights
chmod 750 /usr/local/lib/owncloud/{apps,config}

cp "$1/owncloud.db" $STORAGE_ROOT/owncloud/
cp "$1/config.php" $STORAGE_ROOT/owncloud/

ln -sf $STORAGE_ROOT/owncloud/config.php /usr/local/lib/owncloud/config/config.php
chown -f -R www-data:www-data $STORAGE_ROOT/owncloud /usr/local/lib/owncloud
chown www-data:www-data $STORAGE_ROOT/owncloud/config.php

sudo -u www-data php$PHP_VER /usr/local/lib/owncloud/occ maintenance:mode --off

service php8.2-fpm start
echo "Done"
