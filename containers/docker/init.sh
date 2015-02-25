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

for service in rsyslog dovecot memcached postgrey postfix nginx bind9 fail2ban spampd nsd opendkim opendmarc php5-fpm
do
	# create runit service from source file
	mkdir -p /etc/service/$service
	cp /usr/local/mailinabox/containers/docker/runit/$service.sh /etc/service/$service/run
	chmod +x /etc/service/$service/run

	# runit -> LSB compatibility
	# see http://smarden.org/runit/faq.html#lsb
	if [ -f /etc/init.d/$service ]; then
		mv /etc/init.d/$service /etc/init.d/$service.lsb
		chmod -x /etc/init.d/$service.lsb
	fi
	ln -s /usr/bin/sv /etc/init.d/$service
done

# Start configuration. Using 'source' means an exit from inside
# also exits this script and terminates the container.
cd /usr/local/mailinabox
export IS_DOCKER=1
export DISABLE_FIREWALL=1
source setup/start.sh

