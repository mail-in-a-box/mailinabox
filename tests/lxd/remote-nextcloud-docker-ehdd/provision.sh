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
# from Docker) and an encrypted user-data
#

D=$(dirname "$BASH_SOURCE")
. "$D/../../bin/lx_functions.sh" || exit 1
. "$D/../../bin/provision_functions.sh" || exit 1

# Create the instance (started)
provision_start "" "/mailinabox" || exit 1

# Setup system
provision_shell <<<"
cd /mailinabox
export PRIMARY_HOSTNAME=qa1.abc.com
export FEATURE_MUNIN=false
export EHDD_KEYFILE=\$HOME/keyfile
echo -n 'boo' >\$EHDD_KEYFILE
tests/system-setup/remote-nextcloud-docker.sh || exit 1
tests/runner.sh -no-smtp-remote remote-nextcloud ehdd default || exit 2
"

provision_done $?
