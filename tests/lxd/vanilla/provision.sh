#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


D=$(dirname "$BASH_SOURCE")
. "$D/../../bin/lx_functions.sh" || exit 1
. "$D/../../bin/provision_functions.sh" || exit 1

# Create the instance (started)
provision_start "" "/mailinabox" || exit 1

# Setup system
if [ "$1" = "ciab" ]; then
    # use a remote cloudinabox (does not have to be running)
    provision_shell <<<"
cd /mailinabox
export PRIMARY_HOSTNAME='${inst}.local'
export NC_PROTO=https
export NC_HOST=vanilla-ciab.local
export NC_PORT=443
export NC_PREFIX=/
export SKIP_SYSTEM_UPDATE=0
tests/system-setup/vanilla.sh --qa-ca --enable-mod=remote-nextcloud
rc=$?
if ! ufw status | grep remote_nextcloud >/dev/null; then
   # firewall rules aren't added when ciab is down
   echo 'For testing, allow ldaps from anywhere'
   ufw allow ldaps
fi
echo 'Add smart host alias - so \$NC_HOST can send mail to/via this host'
(
 source tests/lib/all.sh
 rest_urlencoded POST /admin/mail/aliases/add qa@abc.com Test_1234 \"address=@\$NC_HOST\" 'description=smart-host' 'permitted_senders=qa@abc.com' 2>/dev/null
 echo \"\$REST_HTTP_CODE: \$REST_OUTPUT\"
)
exit $rc
"
    provision_done $?

else
    # vanilla (default - no miab integration)
    provision_shell <<<"
cd /mailinabox
export PRIMARY_HOSTNAME='${inst}.local'
#export FEATURE_MUNIN=false
#export FEATURE_NEXTCLOUD=false
export SKIP_SYSTEM_UPDATE=0
tests/system-setup/vanilla.sh
rc=$?
#   --enable-mod=move-postfix-queue-to-user-data
#   --enable-mod=roundcube-master
#   --enable-mod=roundcube-debug
#   --enable-mod=rcmcarddav-composer
exit $rc
"
    provision_done $?

fi
