#!/bin/bash

# Run this on a VM to pre-install all the packages, then
# take a snapshot - it will greatly speed up subsequent
# test installs

#
# What won't be installed:
#
# Nextcloud and Roundcube are downloaded with wget by the setup
# scripts, so they are not included
#
# postfix, postgrey and slapd because they require terminal input
#


if [ ! -d "setup" ]; then
    echo "Run from the miab root directory"
    exit 1
fi


dry_run=true

if [ "$1" == "--no-dry-run" ]; then
    dry_run=false
fi

if $dry_run; then
    echo "WARNING: dry run is TRUE, no changes will be made"
fi


remove_line_continuation() {
    local file="$1"
    awk '
BEGIN            { C=0 } 
C==1 && /[^\\]$/ { C=0; print $0; next } 
C==1             { printf("%s",substr($0,0,length($0)-1)); next } 
/\\$/            { C=1; printf("%s",substr($0,0,length($0)-1)); next } 
                 { print $0 }' \
                     "$file"
}

install_packages() {
    while read line; do
        pkgs=""
        case "$line" in
             apt_install* )
                 pkgs="$(cut -c12- <<<"$line")"
                 ;;
             "apt-get install"* )
                 pkgs="$(cut -c16- <<<"$line")"
                 ;;
             "apt install"* )
                 pkgs="$(cut -c12- <<<"$line")"
                 ;;
        esac
        
        # don't install postfix - causes problems with setup scripts
        # and requires user input. exclude postgrey because it will
        # install postfix as a dependency
        pkgs="$(sed 's/postgrey//g' <<< "$pkgs")"
        pkgs="$(sed 's/postfix-[^ $]*//g' <<<"$pkgs")"
        pkgs="$(sed 's/postfix//g' <<<"$pkgs")"

        # don't install slapd - it requires user input
        pkgs="$(sed 's/slapd//g' <<< "$pkgs")"

        if [ $(. /etc/os-release; echo $VERSION_ID | awk -F. '{print $1}') -ge 22 ];
        then
            # don't install opendmarc on ubuntu 22 and higher - it requires
            # interactive user input
            pkgs="$(sed 's/opendmarc//g' <<< "$pkgs")"
        fi
        
        if [ ! -z "$pkgs" ]; then
            echo "install: $pkgs"
            if ! $dry_run; then
                apt-get install -y -qq $pkgs
            fi
        fi
    done
}

if ! $dry_run; then
    apt-get update -y
    apt-get upgrade -y
    apt-get autoremove -y
fi

for file in $(ls setup/*.sh); do
    remove_line_continuation "$file" | install_packages
done

if ! $dry_run; then
    # bonus
    apt-get install -y -qq openssh-server
    apt-get install -y -qq emacs-nox
    apt-get install -y -qq ntpdate

    # these are added by system-setup scripts and needed for test runner
    apt-get install -y -qq python3-dnspython jq

    # remove apache, which is what setup will do
    apt-get -y -qq purge apache2 apache2-\*

    echo ""
    echo ""
    echo "Done. Take a snapshot...."
    echo ""
fi
