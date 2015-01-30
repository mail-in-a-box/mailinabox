#!/bin/bash

# This script is used within containers to turn it into a Mail-in-a-Box.
# It is referenced by the Dockerfile. You should not run it directly.
########################################################################

# Local configuration details were not known at the time the Docker
# image was created, so all setup is defered until the container
# is started. That's when this script runs.

# If we're not in an interactive shell, set defaults.
if [ ! -t 0 ]; then
	export PUBLIC_IP=auto
	export PUBLIC_IPV6=auto
	export PRIMARY_HOSTNAME=auto
	export CSR_COUNTRY=US
	export NONINTERACTIVE=1
fi

# The phusion/baseimage base image we use for a working Ubuntu
# replaces the normal Upstart system service management with
# a ligher-weight service management system called runit that
# requires a different configuration. We need to create service
# run files that do not daemonize.

# For most of the services, there is a common pattern we can use:
# execute the init.d script that the Ubuntu package installs, and
# then poll for the termination of the daemon.
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
#make_runit_service bind9 named
#make_runit_service fail2ban fail2ban
#make_runit_service mailinabox mailinabox-daemon
#make_runit_service memcached memcached
#make_runit_service nginx nginx
#make_runit_service nsd nsd
#make_runit_service opendkim opendkim
#make_runit_service php5-fpm php5-fpm
#make_runit_service postfix postfix
#make_runit_service postgrey postgrey
#make_runit_service spampd spampd

# Dovecot doesn't provide an init.d script, but it does provide
# a way to launch without daemonization. We wrote a script for
# that specifically.
#
# We also want to use Ubuntu's stock rsyslog rather than syslog-ng
# that the base image provides. Our Dockerfile installs rsyslog.
rm -rf /etc/service/syslog-ng
for service in dovecot; do
	mkdir -p /etc/service/$service
	cp /usr/local/mailinabox/containers/docker/runit/$service.sh /etc/service/$service/run
	chmod +x /etc/service/$service/run
done

# Rsyslog isn't starting automatically but we need it during setup.
service rsyslog start

# Start configuration. Using 'source' means an exit from inside
# also exits this script and terminates the container.
cd /usr/local/mailinabox
export IS_DOCKER=1
export DISABLE_FIREWALL=1
source setup/start.sh

