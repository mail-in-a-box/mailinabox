#!/bin/bash

NAME=php5-fpm
DAEMON=/usr/sbin/$NAME
DAEMON_ARGS="--fpm-config /etc/php5/fpm/php-fpm.conf -F"

# Read configuration variable file if it is present
[ -r /etc/default/$NAME ] && . /etc/default/$NAME

exec $DAEMON $DAEMON_ARGS 2>&1