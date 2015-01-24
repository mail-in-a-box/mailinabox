#!/bin/bash

EXEC=mailinabox
PROCESS=mailinabox-daemon

if [ `ps aux | grep $PROCESS | grep -v grep | wc -l` -eq 0 ]; then
	/etc/init.d/$EXEC start
fi

while [ `ps aux | grep $PROCESS | grep -v grep | wc -l` -gt 0 ]; do
	sleep 30
done
