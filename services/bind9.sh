#!/bin/bash

EXEC=bind9
PROCESS=named

/etc/init.d/$EXEC start

while [ `ps -C $PROCESS -o pid= | wc -l` -gt 0 ]; do
	sleep 30
done

