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
apt_install install -y radicale uwsgi uwsgi-plugin-http uwsgi-plugin-python

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
[logging]
config = $STORAGE_ROOT/radicale/etc/logging
#debug = True
EOF

# Logging config
cat > $STORAGE_ROOT/radicale/etc/logging <<EOF;
# Logging
[loggers]
keys = root
[handlers]
keys = console,file
[formatters]
keys = simple,full
[logger_root]
level = DEBUG
handlers = file
[handler_console]
class = StreamHandler
level = DEBUG
args = (sys.stdout,)
formatter = simple
[handler_file]
class = FileHandler
args = ('$STORAGE_ROOT/radicale/radicale.log',)
level = INFO
formatter = full
[formatter_simple]
format = %(message)s
[formatter_full]
format = %(asctime)s - %(levelname)s: %(message)s
EOF

# WSGI launch file
cat > $STORAGE_ROOT/radicale/radicale.wsgi <<EOF;
#!/usr/bin/env python

import radicale

radicale.log.start()
application = radicale.Application()
EOF

# UWSGI config file
cat > /etc/uwsgi/apps-available/radicale.ini <<EOF;
[uwsgi]
uid = www-data
gid = www-data
socket = /tmp/radicale.sock
plugins = http, python
wsgi-file = $STORAGE_ROOT/radicale/radicale.wsgi
pidfile = $STORAGE_ROOT/radicale/radicale.pid
EOF

# Set proper rights
chown -R www-data:www-data $STORAGE_ROOT/radicale

# Reload Radicale
uwsgi --reload $STORAGE_ROOT/radicale/radicale.pid
