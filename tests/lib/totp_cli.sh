#!/bin/bash

. $(dirname "0")/totp.sh || exit 1

while [ $# -gt 0 ]; do
    arg="$1"
    shift
    if [ "$arg" == "token" ]; then
        # our "authenticator app"
        #
        # get the current token for the secret supplied or if no
        # secret given on the command line, from the saved secret in
        # /tmp/totp_secret.txt
        #
        secret_file="/tmp/totp_secret.txt"
        
        if [ $# -gt 0 ]; then
            recalled=false
            secret="$1"
            shift
            
        else
            recalled=true
            echo "Re-using last secret from $secret_file" 1>&2
            secret="$(cat $secret_file)"
            if [ $? -ne 0 ]; then
                exit 1
            fi
        fi
        
        totp_current_token "$secret"
        code=$?
        if [ $code -ne 0 ]; then
            exit 1
            
        elif ! $recalled; then
            echo "Storing secret in $secret_file" 1>&2
            touch "$secret_file" || exit 2
            chmod 600 "$secret_file" || exit 3
            echo -n "$secret" > "$secret_file" || exit 4
        fi

        exit 0
    fi
done

