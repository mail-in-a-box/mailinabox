#!/bin/bash

. "ehdd/ehdd_funcs.sh" || exit 1

if [ -e "$EHDD_IMG" ]; then
    
    if [ -s /etc/mailinabox.conf ]; then
        echo ""
        echo "** Disabling system services **"
        systemctl disable --quiet postfix
        systemctl disable --quiet dovecot
        systemctl disable --quiet cron
        systemctl disable --quiet nginx
        systemctl disable --quiet php8.0-fpm
        systemctl disable --quiet mailinabox
        systemctl disable --quiet fail2ban
        systemctl disable --quiet miabldap-capture
        #systemctl disable nsd
        [ -x /usr/sbin/slapd ] && systemctl disable --quiet slapd

        echo ""
        echo "IMPORTANT:"
        echo "    Services have been disabled at startup because the encrypted HDD will"
        echo "    be unavailable. Run ehdd/startup.sh after a reboot."
    fi

fi



