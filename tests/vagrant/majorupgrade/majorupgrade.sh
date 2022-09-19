#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


# run from this script's directory
cd $(dirname "$0")

source ../../lib/color-output.sh

warn "Destroy existing VMs"
vagrant destroy -f

artifact_dir_local="$(dirname "$0")/../../out/majorupgrade"
artifact_dir_vm="/mailinabox/tests/out/majorupgrade"
oldvm="major-upgrade-oldvm"
newvm="major-upgrade-newvm"

#
# bring up oldvm
# ... then install, populate, and backup
# ... installed source is in $HOME/miabldap-bionic ($HOME is /root)
#

warn "Bring up $oldvm"
vagrant up $oldvm || exit 1

warn "Run managment/backup.py"
vagrant ssh $oldvm -- "sudo -H bash -c 'cd \$HOME/miabldap-bionic; management/backup.py' && echo 'backup successful'" || exit 2

# copy artifacts from oldvm to host
warn "Copy artifacts"
rm -rf "$artifact_dir_local"
mkdir -p "$artifact_dir_local"
vagrant ssh $oldvm -- "cd \"$artifact_dir_vm\" || exit 1; sudo -H cp -R /tmp/state/oldvm state || exit 2; sudo -H cp -R /home/user-data/backup backup || exit 3"  || exit $?

# destroy oldvm - bring up newvm
warn "Destroy $oldvm - no longer needed"
vagrant destroy $oldvm -f


#
# bring up newvm
#

warn "Bring up $newvm"

# inputs to Vagrantfile passed through environment
export storage_user="user-data"
export duplicity_files="$artifact_dir_vm/backup/encrypted"
export secret_key="$artifact_dir_vm/backup/secret_key.txt"
export restore_to="/home/user-data"
vagrant up $newvm || exit 1

# compare states
vagrant ssh $newvm -- "cd /mailinabox; sudo -H bash -c 'source tests/lib/all.sh; installed_state_compare $artifact_dir_vm/state /tmp/state/newvm'" || exit 2

# run tests
vagrant ssh $newvm -- "cd /mailinabox; sudo -H tests/runner.sh upgrade-basic upgrade-totpuser default" || exit 3

success 'Success'
