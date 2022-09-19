#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####

#
# requires:
#    mailinabox's python installed with pyotp module at
#    /usr/local/lib/mailinabox/env
#

totp_current_token() {
    # given a secret, get the current token
    # token written to stdout
    # error message to stderr
    # return 0 if successful
    # non-zero if an error occured
    local secret="$1"
    /usr/local/lib/mailinabox/env/bin/python -c "import pyotp; totp=pyotp.TOTP(r'$secret'); print(totp.now());"
    if [ $? -ne 0 ]; then
        return 1
    else
        return 0
    fi
}

