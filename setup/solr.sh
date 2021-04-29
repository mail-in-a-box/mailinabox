#!/bin/bash
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
#
# Based on https://forum.iredmail.org/topic17251-dovecot-fts-full-text-search-using-apache-solr-on-ubuntu-1804-lts.html
# https://doc.dovecot.org/configuration_manual/fts/solr/ and https://solr.apache.org/guide/8_8/installing-solr.html
# 
# solr-jetty package is removed from Ubuntu 21.04 onward. This installation 
# therefore depends on manual installation of solr instead of an ubuntu package

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# Install packages and basic configuation
# ---------------------------------------

echo "Installing Solr..."

apt_install dovecot-solr default-jre-headless

VERSION=8.8.2
HASH=7c3e2ed31a4412e7dac48d68c3abd52f75684577

needs_update=0

if [ ! -f /usr/local/lib/solr/bin/solr ]; then
	# not installed yet
	needs_update=1
elif [[ "$VERSION" != `/usr/local/lib/solr/bin/solr version` ]]; then
	# checks if the version is what we want
	needs_update=1
fi

if [ $needs_update == 1 ]; then
	# install SOLR
	wget_verify \
		"https://www.apache.org/dyn/closer.lua?action=download&filename=lucene/solr/$VERSION/solr-$VERSION.tgz" \
		$HASH \
		/tmp/solr-$VERSION.tgz

	tar xzf /tmp/solr-$VERSION.tgz -C /tmp solr-$VERSION/bin/install_solr_service.sh --strip-components=2
	# install to usr/local, force update, do not start service on installation complete
	bash /tmp/install_solr_service.sh /tmp/solr-$VERSION.tgz -i /usr/local/lib -f -n
	
	rm -f /tmp/solr-$VERSION.tgz
	rm -f /tmp/install_solr_service.sh

	# stop and remove the init.d script
	rm -f /etc/init.d/solr
	update-rc.d solr remove
fi

# Add security
tools/editconf.py /etc/default/solr.in.sh \
        SOLR_IP_WHITELIST='"127.0.0.1, [::1]"'

# Change log dir
if [ ! -d "/var/log/solr" ]; then
	mkdir /var/log/solr
fi

chown solr:solr /var/log/solr	

tools/editconf.py /etc/default/solr.in.sh \
		SOLR_LOGS_DIR="/var/log/solr"

# Install systemd service
cp -f conf/solr/solr.service /lib/systemd/system/solr.service 
#	hide_output systemctl link -f /lib/systemd/system/solr.service

# Reload systemctl to pickup the above changes
hide_output systemctl daemon-reload

# Make sure service is enabled
hide_output systemctl enable solr.service

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
  fts_solr = url=http://127.0.0.1:8983/solr/dovecot/
}
EOF

# Install cronjobs to keep FTS up to date.
hide_output install -m 755 conf/cron/miab_dovecot /etc/cron.daily/
hide_output install -m 644 conf/cron/miab_solr /etc/cron.d/

# Initialize solr dovecot instance
if [ ! -d "/var/solr/data/dovecot" ]; then
	# Starting solr might take a while
    echo "Starting solr..."
    hide_output systemctl restart solr.service
		
	sudo -u solr /usr/local/lib/solr/bin/solr create -c dovecot
	rm -f /var/solr/data/dovecot/conf/schema.xml
	rm -f /var/solr/data/dovecot/conf/managed-schema
	rm -f /var/solr/data/dovecot/conf/solrconfig.xml
	cp -f conf/solr/solr-config-7.7.0.xml /var/solr/data/dovecot/conf/solrconfig.xml
	cp -f conf/solr/solr-schema-7.7.0.xml /var/solr/data/dovecot/conf/schema.xml
	chown -R solr:solr /var/solr/data/dovecot/conf/*
fi

# Create new rsyslog config for solr
cat > /etc/rsyslog.d/10-solr.conf <<EOF
# Send solr systemd messages to solr-systemd.log when using systemd
:programname, startswith, "solr" {
 /var/log/solr-systemd.log
 stop
}
EOF

# Also adjust logrotated to the new file and correct user

cat > /etc/logrotate.d/solr-systemd <<EOF
/var/log/solr-systemd.log {
    rotate 4
    weekly
    missingok
    notifempty
    compress
    delaycompress
    create 640 syslog adm
}
EOF

# Restart services to reload solr schema, dovecot plugins and rsyslog changes
restart_service dovecot
restart_service rsyslog

# Restarting solr might take a while
echo "Restarting solr"
hide_output systemctl restart solr.service

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
