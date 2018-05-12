#!/bin/bash

source setup/functions.sh

echo "Installing Mail-in-a-Box system management daemon..."

# DEPENDENCIES

# duplicity is used to make backups of user data. It uses boto
# (via Python 2) to do backups to AWS S3. boto from the Ubuntu
# package manager is too out-of-date -- it doesn't support the newer
# S3 api used in some regions, which breaks backups to those regions.
# See #627, #653.
#
# python-virtualenv is used to isolate the Python 3 packages we
# install via pip from the system-installed packages.
apt_install duplicity python-pip python-virtualenv
hide_output pip2 install --upgrade boto

# Create a virtualenv for the installation of Python 3 packages
# used by the management daemon.
inst_dir=/usr/local/lib/mailinabox
mkdir -p $inst_dir
venv=$inst_dir/env
if [ ! -d $venv ]; then
	virtualenv -ppython3 $venv
fi

# Upgrade pip because the Ubuntu-packaged version is out of date.
hide_output $venv/bin/pip install --upgrade pip

# Install other Python 3 packages used by the management daemon.
# The first line is the packages that Josh maintains himself!
# NOTE: email_validator is repeated in setup/questions.sh, so please keep the versions synced.
# Force acme to be updated because it seems to need it after the
# pip/setuptools breakage (see above) and the ACME protocol may
# have changed (I got an error on one of my systems).
hide_output $venv/bin/pip install --upgrade \
	rtyaml "email_validator>=1.0.0" "free_tls_certificates>=0.1.3" "exclusiveprocess" \
	flask dnspython python-dateutil \
	"idna>=2.0.0" "cryptography==2.2.2" "acme==0.20.0" boto psutil

# CONFIGURATION

# Create a backup directory and a random key for encrypting backups.
mkdir -p $STORAGE_ROOT/backup
if [ ! -f $STORAGE_ROOT/backup/secret_key.txt ]; then
	$(umask 077; openssl rand -base64 2048 > $STORAGE_ROOT/backup/secret_key.txt)
fi


# Download jQuery and Bootstrap local files

# Make sure we have the directory to save to.
assets_dir=$inst_dir/vendor/assets
rm -rf $assets_dir
mkdir -p $assets_dir

# jQuery CDN URL
jquery_version=2.1.4
jquery_url=https://code.jquery.com

# Get jQuery
wget_verify $jquery_url/jquery-$jquery_version.min.js 43dc554608df885a59ddeece1598c6ace434d747 $assets_dir/jquery.min.js

# Bootstrap CDN URL
bootstrap_version=3.3.7
bootstrap_url=https://github.com/twbs/bootstrap/releases/download/v$bootstrap_version/bootstrap-$bootstrap_version-dist.zip

# Get Bootstrap
wget_verify $bootstrap_url e6b1000b94e835ffd37f4c6dcbdad43f4b48a02a /tmp/bootstrap.zip
unzip -q /tmp/bootstrap.zip -d $assets_dir
mv $assets_dir/bootstrap-$bootstrap_version-dist $assets_dir/bootstrap
rm -f /tmp/bootstrap.zip

# Create an init script to start the management daemon and keep it
# running after a reboot.
rm -f /usr/local/bin/mailinabox-daemon # old path
cat > $inst_dir/start <<EOF;
#!/bin/bash
source $venv/bin/activate
exec python `pwd`/management/daemon.py
EOF
chmod +x $inst_dir/start
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
