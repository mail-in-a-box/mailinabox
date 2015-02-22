#!/bin/bash

# Read config file if it is present.
if [ -r /etc/default/postgrey ]
then
    . /etc/default/postgrey
fi

exec /usr/sbin/postgrey $POSTGREY_OPTS 2>&1