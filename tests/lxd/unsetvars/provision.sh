#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


#
# provision a miab-ldap that has a remote nextcloud (using Nextcloud
# from Docker)
#

D=$(dirname "$BASH_SOURCE")
. "$D/../../bin/lx_functions.sh" || exit 1
. "$D/../../bin/provision_functions.sh" || exit 1

# Create the instance (started)
provision_start "" "/mailinabox" || exit 1

# Setup system
provision_shell <<<"
export NONINTERACTIVE=1
export PUBLIC_IP=auto
export PUBLIC_IPV6=auto
export PRIMARY_HOSTNAME=mailinabox.lan  # auto
export SKIP_NETWORK_CHECKS=1
cd /mailinabox
setup/start.sh
"

provision_done $?
