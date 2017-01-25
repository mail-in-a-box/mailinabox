#!/bin/bash

source setup/functions.sh

echo "Installing Mail-in-a-Box system management daemon..."

# Install packages.
# flask, yaml, dnspython, and dateutil are all for our Python 3 management daemon itself.
# duplicity does backups. python-pip is so we can 'pip install boto' for Python 2, for duplicity, so it can do backups to AWS S3.
apt_install python3-flask links duplicity libyaml-dev python3-dnspython python3-dateutil python-pip

# These are required to pip install cryptography.
apt_install build-essential libssl-dev libffi-dev python3-dev

# Install other Python 3 packages used by the management daemon.
# The first line is the packages that Josh maintains himself!
# NOTE: email_validator is repeated in setup/questions.sh, so please keep the versions synced.
hide_output pip3 install --upgrade setuptools

hide_output pip3 install --upgrade \
	rtyaml "email_validator>=1.0.0" "free_tls_certificates>=0.1.3" "exclusiveprocess" \
	"idna>=2.0.0" "cryptography>=1.7.1" boto psutil

# duplicity uses python 2 so we need to get the python 2 package of boto to have backups to S3.
# boto from the Ubuntu package manager is too out-of-date -- it doesn't support the newer
# S3 api used in some regions, which breaks backups to those regions.  See #627, #653.
hide_output pip install --upgrade boto

# Create a backup directory and a random key for encrypting backups.
mkdir -p $STORAGE_ROOT/backup
if [ ! -f $STORAGE_ROOT/backup/secret_key.txt ]; then
	$(umask 077; openssl rand -base64 2048 > $STORAGE_ROOT/backup/secret_key.txt)
fi

# Link the management server daemon into a well known location.
rm -f /usr/local/bin/mailinabox-daemon
ln -s `pwd`/management/daemon.py /usr/local/bin/mailinabox-daemon

# Create an init script to start the management daemon and keep it
# running after a reboot.
rm -f /etc/init.d/mailinabox
ln -s $(pwd)/conf/management-initscript /etc/init.d/mailinabox
hide_output update-rc.d mailinabox defaults

# Remove old files we no longer use.
rm -f /etc/cron.daily/mailinabox-backup
rm -f /etc/cron.daily/mailinabox-statuschecks

# Perform nightly tasks at 3am in system time: take a backup, run
# status checks and email the administrator any changes.

cat > /etc/cron.d/mailinabox-nightly << EOF;
# Mail-in-a-Box --- Do not edit / will be overwritten on update.
# Run nightly tasks: backup, status checks.
0 3 * * *	root	(cd `pwd` && management/daily_tasks.sh)
EOF

# Start the management server.
restart_service mailinabox
