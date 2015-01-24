#!/bin/bash

PROCESS=postgrey

/etc/init.d/$PROCESS start

while [ `ps aux | grep $PROCESS | grep -v grep | wc -l` -gt 0 ]; do
	sleep 30
done

