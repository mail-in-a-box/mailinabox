#!/bin/bash
#
# IMAP search with xapian
# --------------------------------
#
# By default dovecot uses its own Squat search index that has awful performance
# on large mailboxes and is obsolete. Dovecot 2.1+ has support for using Lucene 
# internally but this didn't make it into the Ubuntu packages. Solr uses too 
# much memory. Same goes for elasticsearch. fts xapian might be a good match 
# for mail-in-a-box. See https://github.com/grosjo/fts-xapian

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# Install packages and basic configuation
# ---------------------------------------

echo "Installing fts-xapian..."

apt_install libxapian30

# Update the dovecot plugin configuration
#
# Break-imap-search makes search work the way users expect, rather than the way
# the IMAP specification expects.
tools/editconf.py /etc/dovecot/conf.d/10-mail.conf \
        mail_plugins="fts fts_xapian" \
		mail_home="/home/user-data/mail/homes/%d/%n"

# Install cronjobs to keep FTS up to date.
hide_output install -m 755 conf/cron/miab_dovecot /etc/cron.daily/

# Install files
if [ ! -f /usr/lib/dovecot/decode2text.sh ]; then
	cp -f /usr/share/doc/dovecot-core/examples/decode2text.sh /usr/lib/dovecot
fi

cp -f lib/lib21_fts_xapian_plugin.so /usr/lib/dovecot/modules/

# Create configuration file
cat > /etc/dovecot/conf.d/90-plugin-fts.conf << EOF;
plugin {
  plugin = fts fts_xapian
  
  fts = xapian
  fts_xapian = partial=3 full=20 verbose=0

  fts_autoindex = yes
  fts_enforced = yes

  fts_autoindex_exclude = \Trash
  fts_autoindex_exclude2 = \Junk
  fts_autoindex_exclude3 = \Spam
  
  fts_decoder = decode2text
}

service indexer-worker {
	vsz_limit = 2G
}

service decode2text {
   executable = script /usr/lib/dovecot/decode2text.sh
   user = dovecot
   unix_listener decode2text {
     mode = 0666
   }
}
EOF

restart_service dovecot

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

