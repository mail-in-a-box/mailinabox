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

# Start configuration.
cd /usr/local/mailinabox
export IS_DOCKER=1
export STORAGE_ROOT=/data
export STORAGE_USER=user-data
export DISABLE_FIREWALL=1

mkdir /etc/service/rsyslogd
mkdir /etc/service/bind9
mkdir /etc/service/dovecot
mkdir /etc/service/fail2ban
mkdir /etc/service/mailinabox
mkdir /etc/service/memcached
mkdir /etc/service/nginx
mkdir /etc/service/nsd
mkdir /etc/service/opendkim
mkdir /etc/service/php5-fpm
mkdir /etc/service/postfix
mkdir /etc/service/postgrey
mkdir /etc/service/spampd
cp services/rsyslogd.sh /etc/service/rsyslogd/run
cp services/bind9.sh /etc/service/bind9/run
cp services/dovecot.sh /etc/service/dovecot/run
cp services/fail2ban.sh /etc/service/fail2ban/run
cp services/mailinabox.sh /etc/service/mailinabox/run
cp services/memcached.sh /etc/service/memcached/run
cp services/nginx.sh /etc/service/nginx/run
cp services/nsd.sh /etc/service/nsd/run
cp services/opendkim.sh /etc/service/opendkim/run
cp services/php5-fpm.sh /etc/service/php5-fpm/run
cp services/postfix.sh /etc/service/postfix/run
cp services/postgrey.sh /etc/service/postgrey/run
cp services/spampd.sh /etc/service/spampd/run

rsyslogd
source setup/start.sh
/etc/init.d/mailinabox start
/usr/sbin/dovecot -c /etc/dovecot/dovecot.conf
sleep 5
curl -s -d POSTDATA --user $(</var/lib/mailinabox/api.key): http://127.0.0.1:10222/dns/update
curl -s -d POSTDATA --user $(</var/lib/mailinabox/api.key): http://127.0.0.1:10222/web/update
source setup/firstuser.sh
/etc/init.d/mailinabox stop
kill $(pidof dovecot)
/etc/init.d/resolvconf start
killall rsyslogd
my_init

