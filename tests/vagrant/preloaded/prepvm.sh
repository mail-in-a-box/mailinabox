#!/bin/bash
#####
##### This file is part of Mail-in-a-Box-LDAP which is released under the
##### terms of the GNU Affero General Public License as published by the
##### Free Software Foundation, either version 3 of the License, or (at
##### your option) any later version. See file LICENSE or go to
##### https://github.com/downtownallday/mailinabox-ldap for full license
##### details.
#####


# Run this on a VM to pre-install all the packages, then
# take a snapshot - it will greatly speed up subsequent
# test installs

#
# What won't be installed:
#
# Nextcloud and Roundcube are downloaded with wget by the setup
# scripts, so they are not included
#
# slapd - we want to test installation with setup/ldap.sh
#

if [ ! -d "setup" ]; then
    echo "Run from the miab root directory"
    exit 1
fi

source tests/lib/misc.sh
source tests/lib/system.sh
source tests/lib/color-output.sh

dry_run=true
start=$(date +%s)

if [ "$1" == "--no-dry-run" ]; then
    dry_run=false
fi

if $dry_run; then
    echo "WARNING: dry run is TRUE, no changes will be made"
fi


# prevent apt from running needrestart(1)
export NEEDRESTART_SUSPEND=true

# prevent interaction during package install
export DEBIAN_FRONTEND=noninteractive

# what major version of ubuntu are we installing on?
OS_MAJOR=$(. /etc/os-release; echo $VERSION_ID | awk -F. '{print $1}')


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
    local return_code=0
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
        
        # don't install slapd
        pkgs="$(sed 's/slapd//g' <<< "$pkgs")"

        # manually set PHP_VER if necessary
        if grep "PHP_VER" <<<"$pkgs" >/dev/null; then
            pkgs="$(sed "s/\${*PHP_VER}*/$PHP_VER/g" <<< "$pkgs")"
        fi
        
        if [ ! -z "$pkgs" ]; then
            H2 "install: $pkgs"
            if ! $dry_run; then
                exec_no_output apt-get install -y $pkgs
                let return_code+=$?
            fi
        fi
    done
    return $return_code
}

install_ppas() {
    H1 "Add apt repositories"
    grep 'hide_output add-apt-repository' setup/system.sh |
        while read line; do
            line=$(sed 's/^hide_output //' <<< "$line")
            H2 "$line"
            if ! $dry_run; then
                exec_no_output $line
            fi
        done 
}

add_swap() {
    H1 "Add a swap file to the system"
    if ! $dry_run; then
	    dd if=/dev/zero of=/swapfile bs=1024 count=$[1024*1024] status=none
	    chmod 600 /swapfile
	    mkswap /swapfile
	    swapon /swapfile
	    echo "/swapfile   none    swap    sw    0   0" >> /etc/fstab
    fi
}


# install PPAs from sources
install_ppas

# add swap file
add_swap

# obtain PHP_VER variable from sources
PHP_VER=$(source setup/functions.sh; echo $PHP_VER)


if ! $dry_run; then
    H1 "Upgrade system"
    H2 "apt update"
    exec_no_output apt-get update -y || exit 1
    H2 "apt upgrade"
    exec_no_output apt-get upgrade -y --with-new-pkgs || exit 1
    H2 "apt autoremove"
    exec_no_output apt-get autoremove -y
fi

# without using the same installation order as setup/start.sh, we end
# up with the system's php getting installed in addition to the
# non-system php that may also installed by setup (don't know why,
# probably one of the packages has a dependency). create an ordered
# list of files to process so we get a similar system setup.

setup_files=( $(ls setup/*.sh) )
desired_order=(
    setup/functions.sh
    setup/preflight.sh
    setup/questions.sh
    setup/network-checks.sh
    setup/system.sh
    setup/ssl.sh
    setup/dns.sh
    setup/ldap.sh
    setup/mail-postfix.sh
    setup/mail-dovecot.sh
    setup/mail-users.sh
    setup/dkim.sh
    setup/spamassassin.sh
    setup/web.sh
    setup/webmail.sh
    setup/nextcloud.sh
    setup/zpush.sh
    setup/management.sh
    setup/management-capture.sh
    setup/munin.sh
    setup/firstuser.sh
)
ordered_files=()
for file in "${desired_order[@]}" "${setup_files[@]}"; do
    if [ -e "$file" ] && ! array_contains "$file" "${ordered_files[@]}"; then
        ordered_files+=( "$file" )
    fi
done

failed=0
    
for file in ${ordered_files[@]}; do
    H1 "$file"
    remove_line_continuation "$file" | install_packages
    [ $? -ne 0 ] && let failed+=1
done

if ! $dry_run; then
    # bonus
    H1 "install extras"

    H2 "openssh, emacs, ntpdate, net-tools, jq"
    exec_no_output apt-get install -y openssh-server emacs-nox ntpdate net-tools jq || let failed+=1

    # these are added by system-setup scripts and needed for test runner
    H2 "python3-dnspython"
    exec_no_output apt-get install -y python3-dnspython || let failed+=1
    H2 "pyotp(pip)"
    exec_no_output python3 -m pip install pyotp --quiet || let failed+=1

    # ...and for browser-based tests
    #H2 "x11"  # needed for chromium w/head (not --headless)
    #exec_no_output apt-get install -y xorg openbox xvfb gtk2-engines-pixbuf dbus-x11 xfonts-base xfonts-100dpi xfonts-75dpi xfonts-cyrillic xfonts-scalable x11-apps imagemagick || let failed+=1
    H2 "chromium"
    #exec_no_output apt-get install -y chromium-browser || let failed+=1
    exec_no_output snap install chromium || let failed+=1
    H2 "selenium(pip)"
    exec_no_output python3 -m pip install selenium --quiet || let failed+=1

    # remove apache, which is what setup will do
    H2 "remove apache2"
    exec_no_output apt-get -y purge apache2 apache2-\*

fi

end=$(date +%s)
echo ""
echo ""
if [ $failed -gt 0 ]; then
    echo "$failed failures! ($(elapsed_pretty $start $end))"
    echo ""
    exit 1
else
    echo "Successfully prepped in $(elapsed_pretty $start $end). Take a snapshot...."
    echo ""
    exit 0
fi

