#!/bin/bash
ehdd/mount.sh || exit 1

if [ -s /etc/mailinabox.conf ]; then
    [ -x /usr/sbin/slapd ] && systemctl start slapd
    systemctl start php7.2-fpm
    systemctl start dovecot
    systemctl start postfix
    systemctl start nginx
    systemctl start cron
    #systemctl start nsd
    systemctl link -f $(pwd)/conf/mailinabox.service
    systemctl start fail2ban
    systemctl restart mailinabox
    systemctl start miabldap-capture
    # since postgrey's local client whitelist is in user-data, reload
    # to ensure postgrey daemon has it
    systemctl reload postgrey
fi

