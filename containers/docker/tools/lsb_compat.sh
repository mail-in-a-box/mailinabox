#!/bin/bash

# This removes /etc/init.d service if service exists in runit.
# It also creates a symlink from /usr/bin/sv to /etc/init.d/$service
# to support SysV syntax: service $service <command> or /etc/init.d/$service <command>

SERVICES=/etc/service/*

for f in $SERVICES
do
	service=$(basename "$f")
	if [ -d /etc/service/$service ]; then
		echo "LSB Compatibility for '$service'"
		if [ -f /etc/init.d/$service ]; then
			mv /etc/init.d/$service /etc/init.d/$service.lsb
			chmod -x /etc/init.d/$service.lsb
		fi
		ln -s /usr/bin/sv /etc/init.d/$service
	fi
done