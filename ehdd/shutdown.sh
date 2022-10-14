#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

if [ -s /etc/mailinabox.conf ]; then
    systemctl stop mailinabox
    systemctl stop nginx
    systemctl stop php8.0-fpm
    systemctl stop postfix
    systemctl stop dovecot
    systemctl stop postgrey
    systemctl stop cron
    #systemctl stop nsd
    [ -x /usr/sbin/slapd ] && systemctl stop slapd
    systemctl stop fail2ban
    systemctl stop miabldap-capture
fi

if [ "$1" != "--no-umount" ]; then
    ehdd/umount.sh
    code=$?
    tries=1
    while [ $code -eq 2 -a $tries -le 3 ]; do
        echo "Trying again in 10 seconds..."
        sleep 10
        ehdd/umount.sh
        code=$?
        let tries+=1
    done
else
    code=0
fi

exit $code
