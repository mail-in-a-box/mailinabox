#!/bin/bash

#
# this adds the logwatch tool to the system (see,
# https://ubuntu.com/server/docs/logwatch) and executes it as part of
# normal status checks with it's output attached to daily status
# checks emails
#
# created: 2022-11-03
# author: downtownallday
# removal: run `local/logwatch.sh remove`, then delete symbolic link
#          (`rm local/logwatch.sh`)
#
# Warning for cloud-in-a-box users: if ssmtp (or some other
# mail-transport-agent) is not installed, installing logwatch will
# pull in postfix
#

[ -e /etc/mailinabox.conf ] && source /etc/mailinabox.conf
[ -e /etc/cloudinabox.conf ] && source /etc/cloudinabox.conf
. setup/functions.sh

logwatch_remove() {
    remove_hook_handler "logwatch-hooks.py"
    hide_output apt-get purge logwatch -y
}

logwatch_install() {
    echo "Installing logwatch"
    # also install some perl modules used by our nextcloud logfilter
    apt_install logwatch libjson-perl libtry-tiny-perl
    # remove cron entry added by logwatch installer, which emails daily
    rm -f /etc/cron.daily/00logwatch
    mkdir -p /var/cache/logwatch

    # settings in the logwatch.conf file become defaults when running
    # the cli /usr/sbin/logwatch (cli arguments override the conf
    # file)
    local settings=(
        "MailTo=administrator@$PRIMARY_HOSTNAME"
        "MailFrom=\"$PRIMARY_HOSTNAME\" <administrator@$PRIMARY_HOSTNAME>"
    )
        
    if [ ! -e /etc/logwatch/conf/logwatch.conf ]; then
        cp /usr/share/logwatch/default.conf/logwatch.conf /etc/logwatch/conf/
        settings+=(
            "Output=mail"
            "Format=html"
            "Service=All"
            "Detail=Low"
        )
    fi

    # install our custom logwatch filters
    if [ -d setup/mods.available/conf/logwatch ]; then
        cp -R setup/mods.available/conf/logwatch/* /etc/logwatch/
    fi

    tools/editconf.py /etc/logwatch/conf/logwatch.conf -case-insensitive "${settings[@]}"    
    install_hook_handler "setup/mods.available/hooks/logwatch-hooks.py"
}


if [ "${1:-}" = "remove" ]; then
    logwatch_remove
else
    logwatch_install
fi

