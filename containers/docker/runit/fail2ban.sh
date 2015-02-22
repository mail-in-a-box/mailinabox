#!/bin/bash

NAME=fail2ban
DAEMON=/usr/bin/$NAME-server

# Ad-hoc way to parse out socket file name
SOCKFILE=`grep -h '^[^#]*socket *=' /etc/$NAME/$NAME.conf /etc/$NAME/$NAME.local 2>/dev/null \
          | tail -n 1 | sed -e 's/.*socket *= *//g' -e 's/ *$//g'`
[ -z "$SOCKFILE" ] && SOCKFILE='/tmp/fail2ban.sock'

# Assure that /var/run/fail2ban exists
[ -d /var/run/fail2ban ] || mkdir -p /var/run/fail2ban

# Run as root by default.
FAIL2BAN_USER=root

# Read configuration variable file if it is present
[ -r /etc/default/$NAME ] && . /etc/default/$NAME
DAEMON_ARGS="$FAIL2BAN_OPTS"

exec $DAEMON -f $DAEMON_ARGS 2>&1