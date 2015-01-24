#!/bin/bash

PROCESS=memcached

/etc/init.d/$PROCESS start

while [ `ps -C $PROCESS -o pid= | wc -l` -gt 0 ]; do
	sleep 60
done

