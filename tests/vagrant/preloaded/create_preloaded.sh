#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


# load defaults for MIABLDAP_GIT and FINAL_RELEASE_TAG_BIONIC64 (make available to Vagrantfile)
pushd "../../.." >/dev/null
source tests/system-setup/setup-defaults.sh || exit 1
popd >/dev/null

vagrant destroy -f
rm -f prepcode.txt

for plugin in "vagrant-vbguest" "vagrant-reload"
do
    if ! vagrant plugin list | grep -F "$plugin" >/dev/null; then
        vagrant plugin install "$plugin" || exit 1
    fi
done

vagrant box update


boxes=(
    "preloaded-ubuntu-bionic64"
    "preloaded-ubuntu-jammy64"
)
# preload packages from source of the following git tags. empty string
# means use the current source tree
tags=(
    "$FINAL_RELEASE_TAG_BIONIC64"
    ""
)
try_reboot=(
    false
    true
)
idx=0

for box in "${boxes[@]}"
do
    if [ ! -z "$1" -a "$1" != "$box" ]; then
        let idx+=1
        continue
    fi

    export RELEASE_TAG="${tags[$idx]}"
    vagrant up $box | tee /tmp/$box.out
    upcode=$?

    if [ $upcode -eq 0 -a ! -e "./prepcode.txt" ] && ${try_reboot[$idx]} && grep -F 'Authentication failure' /tmp/$box.out >/dev/null; then
        # note: upcode is 0 only if config.vm.boot_timeout is set.
        # If this works it may be an indication that ruby's internal
        # ssh does not support the algorithm required by the server,
        # or the public key does not match (vagrant and vm out of
        # sync)
        echo ""
        echo "VAGRANT AUTHENTICATION FAILURE - TRYING LOOSER ALLOWED SSHD ALGS"
        if vagrant ssh $box -c "sudo bash -c 'echo PubkeyAcceptedAlgorithms +ssh-rsa > /etc/ssh/sshd_config.d/miabldap.conf; sudo systemctl restart sshd'"; then
            vagrant halt $box
            vagrant up $box
            upcode=$?
        fi
    fi

    if [ $upcode -ne 0 -a ! -e "./prepcode.txt" ] && ${try_reboot[$idx]}
    then        
        # a reboot may be necessary if guest addtions was newly
        # compiled by vagrant plugin "vagrant-vbguest"
        echo ""
        echo "VAGRANT UP RETURNED $upcode -- RETRYING AFTER REBOOT"
        vagrant halt $box
        vagrant up $box
        upcode=$?
    fi

    rm -f /tmp/$box.out
        
    let idx+=1
    prepcode=$(cat "./prepcode.txt")
    rm -f prepcode.txt
    echo ""
    echo "VAGRANT UP RETURNED $upcode"
    echo "PREPVM RETURNED $prepcode"

    if [ "$prepcode" != "0" -o $upcode -ne 0 ]; then
        echo "FAILED!!!!!!!!"
        vagrant destroy -f $box
        exit 1
    fi

    if vagrant ssh $box -- cat /var/run/reboot-required >/dev/null 2>&1; then
        echo "REBOOT REQUIRED"
        vagrant reload $box
    else
        echo "REBOOT NOT REQUIRED"
    fi

    vagrant halt $box
    vagrant package $box
    rm -f $box.box
    mv package.box $box.box

    vagrant destroy -f $box
    cached_name="$(sed 's/preloaded-/preloaded-miabldap-/' <<<"$box")"
    echo "Removing cached box $cached_name"
    if [ -e "../funcs.rb" ]; then
        pushd .. > /dev/null
        vagrant box remove $cached_name
        code=$?
        popd > /dev/null
    else
        vagrant box remove $cached_name
        code=$?
    fi
    echo "Remove cache box result: $code - ignoring"
done
