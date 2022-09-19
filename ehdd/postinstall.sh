#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


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
        echo "    be unavailable. Run ehdd/run-this-after-reboot.sh after a reboot."
    fi

fi



