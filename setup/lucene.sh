#!/bin/bash
# IMAP search with lucene
# --------------------------------
#
# Adapted from https://github.com/Jonty/mailinabox/blob/solr_support/setup/solr.sh
#
# By default dovecot uses its own Squat search index that has awful performance
# on large mailboxes. Dovecot 2.1+ has support for using Lucene internally but
# this didn't make it into the Ubuntu packages, so we maintain our own
# dovecot-lucene package in a ppa.

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# Install packages and basic configuation
# ---------------------------------------

# Add official ppa
hide_output add-apt-repository -y ppa:brock/mailinabox-brocktice

# Install packages
apt_install dovecot-lucene

# Update the dovecot plugin configuration
#
# Break-imap-search makes search work the way users expect, rather than the way
# the IMAP specification expects
tools/editconf.py /etc/dovecot/conf.d/10-mail.conf \
        mail_plugins="$mail_plugins fts fts_lucene"

cat > /etc/dovecot/conf.d/90-plugin.conf << EOF;
plugin {
  fts = lucene
  fts_lucene = whitespace_chars=@.
}
EOF

# PERMISSIONS

# Ensure configuration files are owned by dovecot and not world readable.
chown -R mail:dovecot /etc/dovecot
chmod -R o-rwx /etc/dovecot

# Restart services to reload solr schema & dovecot plugins
restart_service dovecot
