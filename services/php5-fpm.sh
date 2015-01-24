#!/bin/bash

PROCESS=php5-fpm

/etc/init.d/$PROCESS start

while [ `ps -C $PROCESS -o pid= | wc -l` -gt 0 ]; do
	sleep 30
done

