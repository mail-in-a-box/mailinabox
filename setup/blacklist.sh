#!/bin/bash
# Add Blocklist.de malicious IP Addresses to Daily Crontab
# Also IPtables-persistent to save IP addresses upon reboot
# Added by Alon "ChiefGyk" Ganon
# alonganon.info
# alon@ganon.me
source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
apt_install -y ipset 
ipset create blacklist hash:net
iptables -I INPUT -m set --match-set blacklist src -j DROP
cp conf/blacklist/blacklist /etc/cron.daily/blacklist
chmod a+x /etc/cron.daily/blacklist
time /etc/cron.daily/blacklist
apt_install -y iptables-persistent
echo "Blacklist has been installed. It will run daily automatically."