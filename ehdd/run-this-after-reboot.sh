#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

ehdd/mount.sh || exit 1

if [ -s /etc/mailinabox.conf ]; then
    [ -x /usr/sbin/slapd ] && systemctl start slapd
    systemctl start php8.0-fpm
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
    # to ensure postgrey daemon has it.
    #
    # TODO: this should be 'reload' but is broken in jammy (reload fails on a systemctl permissions issue accessing postgrey's pid file)
    systemctl restart postgrey
fi

