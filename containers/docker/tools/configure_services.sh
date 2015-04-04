#!/bin/bash

# The phusion/baseimage base image we use for a working Ubuntu
# replaces the normal Upstart system service management with
# a ligher-weight service management system called runit that
# requires a different configuration. We need to create service
# run files that do not daemonize.

# This removes /etc/init.d service if service exists in runit.
# It also creates a symlink from /usr/bin/sv to /etc/init.d/$service
# to support SysV syntax: service $service <command> or /etc/init.d/$service <command>
SERVICES=/etc/service/*
for f in $SERVICES
do
	service=$(basename "$f")
	if [ -d /etc/service/$service ]; then
		if [ -f /etc/init.d/$service ]; then
			mv /etc/init.d/$service /etc/init.d/$service.lsb
			chmod -x /etc/init.d/$service.lsb
		fi
		ln -s /usr/bin/sv /etc/init.d/$service
	fi
done

# Create runit services from sysv services. For most of the services,
# there is a common pattern we can use: execute the init.d script that
# the Ubuntu package installs, and then poll for the termination of
# the daemon.
function make_runit_service {
	INITD_NAME=$1
	WAIT_ON_PROCESS_NAME=$2
	mkdir -p /etc/service/$INITD_NAME
	cat > /etc/service/$INITD_NAME/run <<EOF;
#!/bin/bash
source /usr/local/mailinabox/setup/functions.sh
hide_output /etc/init.d/$INITD_NAME restart
while [ \`ps a -C $WAIT_ON_PROCESS_NAME -o pid= | wc -l\` -gt 0 ]; do
       sleep 30
done
echo $WAIT_ON_PROCESS_NAME died.
sleep 20
EOF
	chmod +x /etc/service/$INITD_NAME/run
}
make_runit_service bind9 named
make_runit_service resolvconf resolvconf
make_runit_service fail2ban fail2ban
make_runit_service mailinabox mailinabox-daemon
make_runit_service memcached memcached
make_runit_service nginx nginx
make_runit_service nsd nsd
make_runit_service opendkim opendkim
make_runit_service opendmarc opendmarc
make_runit_service php5-fpm php5-fpm
make_runit_service postfix postfix
make_runit_service postgrey postgrey
make_runit_service spampd spampd

# Dovecot doesn't provide an init.d script, but it does provide
# a way to launch without daemonization. We wrote a script for
# that specifically.
for service in dovecot; do
	mkdir -p /etc/service/$service
	cp /usr/local/mailinabox/containers/docker/runit/$service.sh /etc/service/$service/run
	chmod +x /etc/service/$service/run
done

# This adds a log/run file on each runit service directory.
# This file make services stdout/stderr output to svlogd log
# directory located in /var/log/runit/$service.
SERVICES=/etc/service/*
for f in $SERVICES
do
	service=$(basename "$f")
	if [ -d /etc/service/$service ]; then
		mkdir -p /etc/service/$service/log
		cat > /etc/service/$service/log/run <<EOF;
#!/bin/bash
mkdir -p /var/log/runit
chmod o-wrx /var/log/runit
mkdir -p /var/log/runit/$service
chmod o-wrx /var/log/runit/$service
exec svlogd -tt /var/log/runit/$service/
EOF
		chmod +x /etc/service/$service/log/run
	fi
done

# Disable services for now. Until Mail-in-a-Box is installed the
# services won't be configured right and there would be errors if
# they got run prematurely.
SERVICES=/etc/service/*
for f in $SERVICES
do
	service=$(basename "$f")
	if [ "$service" = "syslog-ng" ]; then continue; fi;
	if [ "$service" = "syslog-forwarder" ]; then continue; fi;
	if [ "$service" = "ssh" ]; then continue; fi;
	if [ "$service" = "cron" ]; then continue; fi;
	if ([ -d /etc/service/$service ] && [ ! -f /etc/service/$service/down ]); then
		touch /etc/service/$service/down
	fi
done
