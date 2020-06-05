#!/bin/bash

# Run this on a VM to pre-install all the packages, then
# take a snapshot - it will greatly speed up subsequent
# test installs


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
        pkgs="$(sed s/postfix//g <<<"$pkgs")"
        
        if [ ! -z "$pkgs" ]; then
            echo "install: $pkgs"
            apt-get install $pkgs -y
        fi
    done
}

apt-get update -y
apt-get upgrade -y
apt-get autoremove -y

for file in $(ls setup/*.sh); do
    remove_line_continuation "$file" | install_packages
done

apt-get install openssh-server -y
apt-get install emacs-nox -y

echo ""
echo ""
echo "Done. Take a snapshot...."
echo ""
