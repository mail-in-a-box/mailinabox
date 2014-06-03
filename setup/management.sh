#!/bin/bash

source setup/functions.sh

apt_install python3-flask links rdiff-backup

# Create a backup directory and a random key for encrypting backups.
mkdir -p $STORAGE_ROOT/backup
if [ ! -f $STORAGE_ROOT/backup/secret_key.txt ]; then
	openssl rand -base64 2048 > $STORAGE_ROOT/backup/secret_key.txt
fi

# Link the management server daemon into a well known location.
rm -f /usr/bin/mailinabox-daemon
ln -s `pwd`/management/daemon.py /usr/bin/mailinabox-daemon

# Create an init script to start the management daemon and keep it
# running after a reboot.
rm -f /etc/init.d/mailinabox
ln -s $(pwd)/conf/management-initscript /etc/init.d/mailinabox
update-rc.d mailinabox defaults

# Start it.
service mailinabox restart
