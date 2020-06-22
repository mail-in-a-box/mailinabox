#!/bin/bash

. "ehdd/ehdd_funcs.sh" || exit 1

if [ -e "$EHDD_IMG" ]; then
    
    if [ -s /etc/mailinabox.conf ]; then
        echo ""
        echo "** Disabling system services **"
        systemctl disable postfix
        systemctl disable dovecot
        systemctl disable cron
        systemctl disable nginx
        systemctl disable php7.2-fpm
        systemctl disable mailinabox
        systemctl disable fail2ban
        #systemctl disable nsd
        [ -x /usr/sbin/slapd ] && systemctl disable slapd

        echo ""
        echo "IMPORTANT:"
        echo "    Services have been disabled at startup because the encrypted HDD will"
        echo "    be unavailable. Run ehdd/startup.sh after a reboot."
    fi

fi



