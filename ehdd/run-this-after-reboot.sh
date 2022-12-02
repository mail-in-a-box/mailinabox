#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

if [ "${1:-}" != "--no-mount" ]; then
    ehdd/mount.sh || exit 1
fi

.  ehdd/ehdd_funcs.sh || exit 1

if system_installed_with_encryption_at_rest; then
    [ -x /usr/sbin/slapd ] && systemctl start slapd
    systemctl start php8.0-fpm
    systemctl start dovecot
    systemctl start postfix
    # postgrey's main database and local client whitelist are in user-data
    systemctl start postgrey
    systemctl start nginx
    systemctl start cron
    #systemctl start nsd
    systemctl link -q -f /lib/systemd/system/mailinabox.service
    systemctl start fail2ban
    systemctl start mailinabox
    systemctl start miabldap-capture
fi

