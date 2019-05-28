#!/bin/bash
#
# Inspired by the solr.sh from jkaberg (https://github.com/jkaberg/mailinabox-sogo)
# with some modifications
#
# IMAP search with lucene via solr
# --------------------------------
#
# By default dovecot uses its own Squat search index that has awful performance
# on large mailboxes. Dovecot 2.1+ has support for using Lucene internally but
# this didn't make it into the Ubuntu packages, so we use Solr instead to run
# Lucene for us.
#
# Solr runs as a Jetty process. The dovecot solr plugin talks to solr via its
# HTTP interface, searching indexed mail and returning results back to dovecot.

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# Install packages and basic configuation
# ---------------------------------------

echo "Installing Solr..."

# Install packages
apt_install solr-jetty dovecot-solr

# Solr requires a schema to tell it how to index data, this is provided by dovecot
cp /usr/share/dovecot/solr-schema.xml /etc/solr/conf/schema.xml

# Update the dovecot plugin configuration
#
# Break-imap-search makes search work the way users expect, rather than the way
# the IMAP specification expects.
# https://wiki.dovecot.org/Plugins/FTS/Solr
# "break-imap-search : Use Solr also for indexing TEXT and BODY searches.
# This makes your server non-IMAP-compliant."
tools/editconf.py /etc/dovecot/conf.d/10-mail.conf \
        mail_plugins="fts fts_solr"

cat > /etc/dovecot/conf.d/90-plugin-fts.conf << EOF;
plugin {
  fts = solr
  fts_autoindex = yes
  fts_solr = break-imap-search url=http://127.0.0.1:8080/solr/
}
EOF

# Install cronjobs to keep FTS up to date.
hide_output install -m 755 conf/cronjob/dovecot /etc/cron.daily/
hide_output install -m 644 conf/cronjob/solr /etc/cron.d/

# PERMISSIONS

# Ensure configuration files are owned by dovecot and not world readable.
chown -R mail:dovecot /etc/dovecot
chmod -R o-rwx /etc/dovecot

# Newer updates to jetty9 restrict write directories, this allows for
# jetty to write to solr database directories
mkdir -p /etc/systemd/system/jetty9.service.d/
cat > /etc/systemd/system/jetty9.service.d/solr-permissions.conf << EOF
[Service]
ReadWritePaths=/var/lib/solr/
ReadWritePaths=/var/lib/solr/data/
EOF

# Reload systemctl to pickup the above override.
systemctl daemon-reload

# Fix Logging
# Due to the new systemd security permissions placed when running jetty.
# The log file directory at /var/log/jetty9 is reset to jetty:jetty
# at every program start.  This causes syslog to fail to add the
# rsyslog filtered output to this folder.  We will move this up a
# directory to /var/log/ since solr-jetty is quite noisy.

# Remove package config file since it points to a folder that
# it does not have permissions to, and is also too far down the
# /etc/rsyslog.d/ order to work anyway.
rm -f /etc/rsyslog.d/jetty9.conf 

# Create new rsyslog config for jetty9 for its new location
cat > /etc/rsyslog.d/10-jetty9.conf <<EOF
# Send Jetty messages to jetty-console.log when using systemd

:programname, startswith, "jetty9" {
 /var/log/jetty-console.log
 stop
}
EOF

# Also adjust logrotated to the new file and correct user
cat > /etc/logrotate.d/jetty9.conf <<EOF
/var/log/jetty-console.log {
    copytruncate
    weekly
    rotate 12
    compress
    delaycompress
    missingok
    create 640 syslog adm
}
EOF


# Restart services to reload solr schema, dovecot plugins and rsyslog changes
restart_service jetty9
restart_service dovecot
restart_service rsyslog

# Kickoff building the index

# Per doveadm-fts manpage: Scan what mails exist in the full text search index
# and compare those to what actually exist in mailboxes.
# This removes mails from the index that have already been expunged  and  makes
# sure that the next doveadm index will index all the missing mails (if any).
doveadm fts rescan -A

# Adds unindexed files to the fts database
# * `-q`: Queues the indexing to be run by indexer process. (will background the indexing)
# * `-A`: All users
# * `'*'`: All folders
doveadm index -q -A '*'
