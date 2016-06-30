#!/bin/bash
# Add Blocklist.de malicious IP Addresses to Daily Crontab
# Also IPtables-persistent to save IP addresses upon reboot
# Added by Alon "ChiefGyk" Ganon
# Original project is here https://github.com/ChiefGyk/ipset-assassin
# alonganon.info
# alon@ganon.me
source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

cp conf/blacklist /etc/cron.daily/blacklist
chmod a+x /etc/cron.daily/blacklist
source setup/tor.sh
echo iptables-persistent iptables-persistent/autosave_v4 boolean false | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean false | debconf-set-selections
apt_install -y ipset dialog iptables-persistent
cp conf/iptables-persistent /etc/init.d/iptables-persistent
ipset create blacklist hash:net
iptables -I INPUT -m set --match-set blacklist src -j DROP
time /etc/cron.daily/blacklist
source setup/dialog.sh
/etc/init.d/iptables-persistent save
echo "Blacklist has been installed. It will run daily automatically."
