#!/bin/bash
if [ -s /etc/mailinabox.conf ]; then
    systemctl stop mailinabox
    systemctl stop nginx
    systemctl stop php7.2-fpm
    systemctl stop postfix
    systemctl stop dovecot
    systemctl stop cron
    #systemctl stop nsd
    [ -x /usr/sbin/slapd ] && systemctl stop slapd
    systemctl stop fail2ban
fi

ehdd/umount.sh
