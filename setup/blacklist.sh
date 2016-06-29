#!/bin/bash
# Add Blocklist.de malicious IP Addresses to Daily Crontab
# Also IPtables-persistent to save IP addresses upon reboot
# Added by Alon "ChiefGyk" Ganon
# Original project is here https://github.com/ChiefGyk/ipset-assassin
# alonganon.info
# alon@ganon.me
source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

apt_install -y ipset 
ipset create blacklist hash:net
iptables -I INPUT -m set --match-set blacklist src -j DROP
cp conf/blacklist/blacklist /etc/cron.daily/blacklist
chmod a+x /etc/cron.daily/blacklist
time /etc/cron.daily/blacklist
iptables-save > /etc/iptables.up.rules
sed -i -e "\$apre-up ipset restore < /etc/ipset.up.rules" /etc/network/interfaces
sed -e "\$apost up iptables-restore < /etc/iptables.up.rules" /etc/network/interfaces
echo "Blacklist has been installed. It will run daily automatically."
