#!/bin/bash

source setup/functions.sh
source /etc/mailinabox.conf # load global vars

echo "Installing Mail-in-a-Box system management daemon..."

# DEPENDENCIES

# duplicity is used to make backups of user data.
#
# virtualenv is used to isolate the Python 3 packages we
# install via pip from the system-installed packages.
#
# certbot installs EFF's certbot which we use to
# provision free TLS certificates.
apt_install duplicity python3-pip virtualenv certbot rsync

# b2sdk is used for backblaze backups.
# boto3 is used for amazon aws backups.
# Both are installed outside the pipenv, so they can be used by duplicity
hide_output pip3 install --upgrade b2sdk boto3

# Create a virtualenv for the installation of Python 3 packages
# used by the management daemon.
inst_dir=/usr/local/lib/mailinabox
mkdir -p $inst_dir
venv=$inst_dir/env
if [ ! -d $venv ]; then
	# A bug specific to Ubuntu 22.04 and Python 3.10 requires
	# forcing a virtualenv directory layout option (see #2335
	# and https://github.com/pypa/virtualenv/pull/2415). In
	# our issue, reportedly installing python3-distutils didn't
	# fix the problem.)
	export DEB_PYTHON_INSTALL_LAYOUT='deb'
	hide_output virtualenv -ppython3 $venv
fi

# Upgrade pip because the Ubuntu-packaged version is out of date.
hide_output $venv/bin/pip install --upgrade pip

# Install other Python 3 packages used by the management daemon.
# The first line is the packages that Josh maintains himself!
# NOTE: email_validator is repeated in setup/questions.sh, so please keep the versions synced.
hide_output $venv/bin/pip install --upgrade \
	rtyaml "email_validator>=1.0.0" "exclusiveprocess" \
	flask dnspython python-dateutil expiringdict gunicorn \
	qrcode[pil] pyotp \
	"idna>=2.0.0" "cryptography==37.0.2" psutil postfix-mta-sts-resolver \
	b2sdk boto3

# CONFIGURATION

# Create a backup directory and a random key for encrypting backups.
mkdir -p "$STORAGE_ROOT/backup"
if [ ! -f "$STORAGE_ROOT/backup/secret_key.txt" ]; then
	(umask 077; openssl rand -base64 2048 > "$STORAGE_ROOT/backup/secret_key.txt")
fi


# Download jQuery and Bootstrap local files

# Make sure we have the directory to save to.
assets_dir=$inst_dir/vendor/assets
rm -rf $assets_dir
mkdir -p $assets_dir

# jQuery CDN URL
jquery_version=2.2.4
jquery_url=https://code.jquery.com

# Get jQuery
wget_verify $jquery_url/jquery-$jquery_version.min.js 69bb69e25ca7d5ef0935317584e6153f3fd9a88c $assets_dir/jquery.min.js

# Bootstrap CDN URL
bootstrap_version=3.4.1
bootstrap_url=https://github.com/twbs/bootstrap/releases/download/v$bootstrap_version/bootstrap-$bootstrap_version-dist.zip

# Get Bootstrap
wget_verify $bootstrap_url 0bb64c67c2552014d48ab4db81c2e8c01781f580 /tmp/bootstrap.zip
unzip -q /tmp/bootstrap.zip -d $assets_dir
mv $assets_dir/bootstrap-$bootstrap_version-dist $assets_dir/bootstrap
rm -f /tmp/bootstrap.zip

# Create an init script to start the management daemon and keep it
# running after a reboot.
# Set a long timeout since some commands take a while to run, matching
# the timeout we set for PHP (fastcgi_read_timeout in the nginx confs).
# Note: Authentication currently breaks with more than 1 gunicorn worker.
cat > $inst_dir/start <<EOF;
#!/bin/bash
# Set character encoding flags to ensure that any non-ASCII don't cause problems.
export LANGUAGE=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LC_TYPE=en_US.UTF-8

mkdir -p /var/lib/mailinabox
tr -cd '[:xdigit:]' < /dev/urandom | head -c 32 > /var/lib/mailinabox/api.key
chmod 640 /var/lib/mailinabox/api.key

source $venv/bin/activate
export PYTHONPATH=$PWD/management
exec gunicorn -b localhost:10222 -w 1 --timeout 630 wsgi:app
EOF
chmod +x $inst_dir/start
cp --remove-destination conf/mailinabox.service /lib/systemd/system/mailinabox.service # target was previously a symlink so remove it first
hide_output systemctl link -f /lib/systemd/system/mailinabox.service
hide_output systemctl daemon-reload
hide_output systemctl enable mailinabox.service

# Perform nightly tasks at 3am in system time: take a backup, run
# status checks and email the administrator any changes.

minute=$((RANDOM % 60))  # avoid overloading mailinabox.email
cat > /etc/cron.d/mailinabox-nightly << EOF;
# Mail-in-a-Box --- Do not edit / will be overwritten on update.
# Run nightly tasks: backup, status checks.
$minute 1 * * *	root	(cd $PWD && management/daily_tasks.sh)
EOF

# Start the management server.
restart_service mailinabox
