#!/bin/bash

source setup/functions.sh

echo "Installing Mail-in-a-Box system management daemon..."

# DEPENDENCIES

# Install Python packages that are available from the Ubuntu
# apt repository:
# flask, yaml, dnspython, and dateutil are all for our Python 3 management daemon itself.
# duplicity does backups. python-pip is so we can 'pip install boto' for Python 2, for duplicity, so it can do backups to AWS S3.
apt_install python3-flask links duplicity libyaml-dev python3-dnspython python3-dateutil python-pip

# These are required to pip install cryptography.
apt_install build-essential libssl-dev libffi-dev python3-dev

# pip<6.1 + setuptools>=34 have a problem with packages that
# try to update setuptools during installation, like cryptography.
# See https://github.com/pypa/pip/issues/4253. The Ubuntu 14.04
# package versions are pip 1.5.4 and setuptools 3.3. When we
# install cryptography under those versions, it tries to update
# setuptools to version 34, which now creates the conflict, and
# then pip gets permanently broken with errors like
# "ImportError: No module named 'packaging'".
#
# Let's test for the error:
if ! python3 -c "from pkg_resources import load_entry_point" 2&> /dev/null; then
	# This system seems to be broken already.
	echo "Fixing broken pip and setuptools..."
	rm -rf /usr/local/lib/python3.4/dist-packages/{pkg_resources,setuptools}*
	apt-get install --reinstall python3-setuptools python3-pip python3-pkg-resources
fi
#
# The easiest work-around on systems that aren't already broken is
# to upgrade pip (to >=9.0.1) and setuptools (to >=34.1) individually
# before we install any package that tries to update setuptools.
hide_output pip3 install --upgrade pip
hide_output pip3 install --upgrade setuptools

# Install other Python 3 packages used by the management daemon.
# The first line is the packages that Josh maintains himself!
# NOTE: email_validator is repeated in setup/questions.sh, so please keep the versions synced.
# Force acme to be updated because it seems to need it after the
# pip/setuptools breakage (see above) and the ACME protocol may
# have changed (I got an error on one of my systems).
hide_output pip3 install --upgrade \
	rtyaml "email_validator>=1.0.0" "free_tls_certificates>=0.1.3" "exclusiveprocess" \
	"idna>=2.0.0" "cryptography>=1.0.2" acme boto psutil

# duplicity uses python 2 so we need to get the python 2 package of boto to have backups to S3.
# boto from the Ubuntu package manager is too out-of-date -- it doesn't support the newer
# S3 api used in some regions, which breaks backups to those regions.  See #627, #653.
hide_output pip2 install --upgrade boto

# CONFIGURATION

# Create a backup directory and a random key for encrypting backups.
mkdir -p $STORAGE_ROOT/backup
if [ ! -f $STORAGE_ROOT/backup/secret_key.txt ]; then
	$(umask 077; openssl rand -base64 2048 > $STORAGE_ROOT/backup/secret_key.txt)
fi


# Download jQuery and Bootstrap local files
 if [ ! -d $HOME/mailinabox/management/static ]; then

   js_lib=$HOME/mailinabox/management/static/assets/js/lib
   css_lib=$HOME/mailinabox/management/static/assets/css/lib

	 # jQuery CDN URL
	 jquery_version=2.1.4
   jquery_url=https://code.jquery.com

   # Bootstrap CDN URL
   bootstrap_version=3.3.7
   bootstrap_url=https://maxcdn.bootstrapcdn.com/bootstrap/$bootstrap_version

	# Get the Javascript files
	if [ ! -d $js_lib ]; then
		mkdir -p $js_lib

		wget_verify $jquery_url/jquery-$jquery_version.min.js 43dc554608df885a59ddeece1598c6ace434d747 $js_lib/jquery.min.js
		wget_verify $bootstrap_url/js/bootstrap.min.js 430a443d74830fe9be26efca431f448c1b3740f9 $js_lib/bootstrap.min.js
	fi

	# Get the CSS(map) files
	if [ ! -d $css_lib ]; then
		mkdir -p $css_lib

		wget_verify $bootstrap_url/css/bootstrap-theme.min.css 8256575374f430476bdcd49de98c77990229ce31 $css_lib/bootstrap-theme.min.css
		wget_verify $bootstrap_url/css/bootstrap-theme.min.css.map 87f7dfd79d77051ac2eca7d093d961fbd1c8f6eb $css_lib/bootstrap-theme.min.css.map
		wget_verify $bootstrap_url/css/bootstrap.min.css 6527d8bf3e1e9368bab8c7b60f56bc01fa3afd68 $css_lib/bootstrap.min.css
		wget_verify $bootstrap_url/css/bootstrap.min.css.map e0d7b2bde55a0bac1b658a507e8ca491a6729e06 $css_lib/bootstrap.min.css.map
	fi
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
