#!/bin/bash

EHDD_IMG="$(setup/ehdd/create_hdd.sh -location)"
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
        echo "    be unavailable. Run tools/startup.sh after a reboot."
    fi

fi

# run local modifications
h=$(hostname --fqdn 2>/dev/null || hostname)
count=0
for d in local/mods.sh local/mods-${h}.sh; do
    if [ -e $d ]; then
        let count+=1
        if ! ./$d; then
            echo "Local modification script $d failed"
            exit 1
        fi
    fi
done


