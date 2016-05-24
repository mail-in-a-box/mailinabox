#!/bin/bash
# Radicale
##########################

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# ### Installing Radicale

echo "Installing Radicale (contacts/calendar)..."

# Cleanup after Owncloud install

if [ -d /usr/local/lib/owncloud ]; then
	rm -rf /usr/local/lib/owncloud
fi
apt-get purge -qq -y owncloud*

# Install radicale
apt_install radicale

# Create radicale directories and set proper rights
mkdir -p $STORAGE_ROOT/radicale/etc/
chown -R www-data:www-data $STORAGE_ROOT/radicale

# Create log directory and make radicale owner
mkdir -p /var/log/radicale
chown -R radicale:radicale /var/log/radicale

# Enable radicale on boot
sed -i '/#ENABLE_RADICALE=yes/c\ENABLE_RADICALE=yes' /etc/default/radicale

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

# Reload radicale so that Radicale starts
restart_service radicale
