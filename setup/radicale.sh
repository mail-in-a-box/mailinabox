#!/bin/bash
# Radicale
##########################

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# ### Installing Radicale

echo "Installing Radicale (contacts/calendar)..."

# Cleanup after Owncloud

if [ -d $STORAGE_ROOT/owncloud ]; then
	rm -rf $STORAGE_ROOT/owncloud
fi

if [ -d /usr/local/lib/owncloud ]; then
	rm -rf /usr/local/lib/owncloud
fi

apt-get purge -qq -y owncloud*

# Install it
apt_install radicale uwsgi uwsgi-core

# Create Directories
mkdir -p $STORAGE_ROOT/radicale/etc/
mkdir -p /var/log/radicale

# Radicale Config file
cat > /etc/radicale/config <<EOF;
[server]
hosts = 127.0.0.1:5232
daemon = True
base_prefix = /radicale/
can_skip_base_prefix = False
[well-known]
caldav = '/%(user)s/caldav/'
carddav = '/%(user)s/carddav/'
[auth]
type = IMAP
imap_hostname = localhost
imap_port = 993
imap_ssl = True
[rights]
type = from_file
file = $STORAGE_ROOT/radicale/etc/rights
[storage]
filesystem_folder = $STORAGE_ROOT/radicale/collections
EOF

# Radicale rights config
cat > $STORAGE_ROOT/radicale/etc/rights <<EOF;
[admin]
user: ^admin.*$
collection: .*
permission: r
[public]
user: .*
collection: ^public(/.+)?$
permission: rw
[domain-wide-access]
user: ^.+@(.+)\..+$
collection: ^{0}/.+$
permission: r
[owner-write]
user: .+
collection: ^%(login)s/.*$
permission: w
EOF

# WSGI launch file
cat > $STORAGE_ROOT/radicale/radicale.wsgi <<EOF;
#!/usr/bin/env python

import radicale

radicale.log.start()
application = radicale.Application()
EOF

# UWSGI config file
cat > /etc/uwsgi/apps-available/radicale <<EOF;
[uwsgi]
uid = www-data
gid = www-data
plugins = http, python
wsgi-file = $STORAGE_ROOT/radicale/radicale.wsgi
EOF

# Enabled the uwsgi app
ln -s /etc/uwsgi/apps-available/radicale /etc/uwsgi/apps-enabled/radicale

# Set proper rights
chown -R www-data:www-data $STORAGE_ROOT/radicale

# Reload uwsgi so that Radicale starts
service uwsgi reload
