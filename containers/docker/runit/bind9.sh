#!/bin/bash

# for a chrooted server: "-u bind -t /var/lib/named"
# Don't modify this line, change or create /etc/default/bind9.
OPTIONS=""
RESOLVCONF=no

test -f /etc/default/bind9 && . /etc/default/bind9

# dirs under /var/run can go away on reboots.
mkdir -p /var/run/named
chmod 775 /var/run/named
chown root:bind /var/run/named >/dev/null 2>&1 || true

exec named -f $OPTIONS 2>&1
