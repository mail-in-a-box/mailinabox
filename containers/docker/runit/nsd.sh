#!/bin/bash

NAME=nsd    
DAEMON=/usr/sbin/$NAME
CONFFILE=/etc/nsd/nsd.conf
DAEMON_ARGS="-d -c $CONFFILE"

# reconfigure since the ip may have changed
# if it fails runit will retry anyway, but
# don't do this on first start
if [ -f /var/lib/mailinabox/api.key ]; then
	/usr/local/mailinabox/tools/dns_update
fi

exec $DAEMON $DAEMON_ARGS 2>&1
