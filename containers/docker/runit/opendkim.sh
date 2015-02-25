#!/bin/bash

DAEMON=/usr/sbin/opendkim
NAME=opendkim
USER=opendkim
RUNDIR=/var/run/$NAME
SOCKET=local:$RUNDIR/$NAME.sock

# Include opendkim defaults if available
if [ -f /etc/default/opendkim ] ; then
        . /etc/default/opendkim
fi

if [ -f /etc/opendkim.conf ]; then
        CONFIG_SOCKET=`awk '$1 == "Socket" { print $2 }' /etc/opendkim.conf`
fi

# This can be set via Socket option in config file, so it's not required
if [ -n "$SOCKET" -a -z "$CONFIG_SOCKET" ]; then
        DAEMON_OPTS="-p $SOCKET $DAEMON_OPTS"
fi

DAEMON_OPTS="-f -x /etc/opendkim.conf -u $USER $DAEMON_OPTS"

exec $DAEMON $DAEMON_OPTS 2>&1