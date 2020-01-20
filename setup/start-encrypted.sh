#!/bin/bash
EHDD_IMG="$(setup/ehdd/create_hdd.sh -location)"

[ -e /etc/mailinabox.conf ] && . /etc/mailinabox.conf

if [ ! -e "$EHDD_IMG" -a ! -z "$STORAGE_ROOT" -a \
       -e "$STORAGE_ROOT/ssl/ssl_private_key.pem" ]; then
    
    echo "System installed without encryption-at-rest"

elif [ ! -e "$EHDD_IMG" ]; then
    
    echo "Creating a new encrypted HDD."
    echo -n "How big should it be? Enter a number in gigabytes: "
    read gb
    setup/ehdd/create_hdd.sh "$gb" || exit 1
    
fi


if setup/ehdd/mount.sh; then
    setup/start.sh $@
    if [ $? -eq 0 ]; then
        setup/ehdd/postinstall.sh || exit 1
    else
        echo "setup/start.sh failed"
    fi
fi

