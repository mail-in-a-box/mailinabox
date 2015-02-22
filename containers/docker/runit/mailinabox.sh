#!/bin/bash

NAME=mailinabox
DAEMON=/usr/local/bin/mailinabox-daemon

export LANGUAGE=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LC_TYPE=en_US.UTF-8

# Read configuration variable file if it is present
[ -r /etc/default/$NAME ] && . /etc/default/$NAME

exec $DAEMON 2>&1