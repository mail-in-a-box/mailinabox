#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


#
# the system must have been populated proir to any upgrade with one of
# the tests/system-setup/populate scripts to use this suite
#
# supply the name of the populate script that was used as an argument
# eg. if basic-populate.sh was used to populate, supply "basic" to the
# script as an argument
#


verify_populate() {    
    local populate_name="$1"
    local verify_script="system-setup/populate/${populate_name}-verify.sh"

    test_start "verify '$populate_name' population set"

    if [ ! -e "$verify_script" ]; then
        test_failure "Verify script $(basename "$verify_script") does not exist"

    else
        record "[run verify-upgrade script $verify_script]"
        local output rc
        output=$("$verify_script" 2>>$TEST_OF)
        rc=$?
        if [ $rc -ne 0 ]
        then
           if [ $rc -eq 127 ]; then
               test_failure "verify script would not run (wd=$(pwd))"
           else
               test_failure "verify script exited with $rc: $output"
           fi
        fi
    fi

    test_end
}



suite_start "upgrade-$1"

export ASSETS_DIR
export MIAB_DIR

verify_populate "$1"

suite_end
