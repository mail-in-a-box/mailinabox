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

