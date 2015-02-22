#!/bin/sh

DAEMON=/usr/sbin/opendmarc
NAME=opendmarc
USER=opendmarc
RUNDIR=/var/run/$NAME
SOCKET=local:$RUNDIR/$NAME.sock

# Include opendkim defaults if available
if [ -f /etc/default/opendmarc ] ; then
        . /etc/default/opendmarc
fi

if [ -f /etc/opendmarc.conf ]; then
        CONFIG_SOCKET=`awk '$1 == "Socket" { print $2 }' /etc/opendmarc.conf`
fi

# This can be set via Socket option in config file, so it's not required
if [ -n "$SOCKET" -a -z "$CONFIG_SOCKET" ]; then
        DAEMON_OPTS="-p $SOCKET $DAEMON_OPTS"
fi

DAEMON_OPTS="-f -c /etc/opendmarc.conf -u $USER $DAEMON_OPTS"

exec $DAEMON $DAEMON_OPTS 2>&1
