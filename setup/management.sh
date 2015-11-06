#!/bin/bash

source setup/functions.sh

echo "Installing Mail-in-a-Box system management daemon..."

# build-essential libssl-dev libffi-dev python3-dev: Required to pip install cryptography.
apt_install python3-flask links duplicity libyaml-dev python3-dnspython python3-dateutil \
	build-essential libssl-dev libffi-dev python3-dev python-pip
hide_output pip3 install --upgrade rtyaml email_validator>=1.0.0 idna>=2.0.0 cryptography>=1.0.2 boto

# duplicity uses python 2 so we need to use the python 2 package of boto
hide_output pip install --upgrade boto

# email_validator is repeated in setup/questions.sh

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

# Perform a daily backup.
cat > /etc/cron.d/mailinabox-backup << EOF;
# /etc/cron.d/mailinabox-backup: crontab fragment to run maininabox-backup
#  This executes mailinabox-backup at 3am.

0 3 * * *	root	$(pwd)/management/backup.py
EOF

# Perform daily status checks. Compare each day to the previous
# for changes and mail the changes to the administrator.
cat > /etc/cron.daily/mailinabox-statuschecks << EOF;
#!/bin/bash
# Mail-in-a-Box --- Do not edit / will be overwritten on update.
# Run status checks.
$(pwd)/management/status_checks.py --show-changes --smtp
EOF
chmod +x /etc/cron.daily/mailinabox-statuschecks


# Start it.
restart_service mailinabox
