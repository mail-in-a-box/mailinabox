#!/bin/bash
#
# This script will remove Nextcloud from your MiaB server
##################################################################

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root."
	exit
fi

# Backup the existing ownCloud/Nextcloud.
# Create a backup directory to store the current installation and database to

BACKUP_DIRECTORY=$STORAGE_ROOT/owncloud-backup/`date +"%Y-%m-%d-%T"`
mkdir -p "$BACKUP_DIRECTORY"
if [ -d /usr/local/lib/owncloud/ ]; then
	echo "Backing up existing Nextcloud installation, configuration, and database to directory to $BACKUP_DIRECTORY..."
	cp -r /usr/local/lib/owncloud "$BACKUP_DIRECTORY/owncloud-install"
	rm -r /usr/local/lib/owncloud
fi
if [ -e $STORAGE_ROOT/owncloud/owncloud.db ]; then
	cp $STORAGE_ROOT/owncloud/owncloud.db $BACKUP_DIRECTORY
fi
if [ -e $STORAGE_ROOT/owncloud/config.php ]; then
	cp $STORAGE_ROOT/owncloud/config.php $BACKUP_DIRECTORY
fi
if [ -d $STORAGE/owncloud/ ]; then
	echo "Removing Nextcloud..."
	rm -r $STORAGE_ROOT/owncloud
fi
# Remove Nextcloud's dependencies
apt_purge php-imap php-pear php-dev php-xml php-zip php-apcu php-imagick
