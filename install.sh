#!/bin/bash
# Add multiple lists of malicious IP Addresses by Daily Crontab
# Also makes ipset and iptables persistent upon reboot
# Added by Alon "ChiefGyk" Ganon
# alonganon.info
# alon@ganon.me

# Are we running as root?
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root. Please re-run like this:"
	echo
	echo "sudo $0"
	echo
	exit
fi
echo iptables-persistent iptables-persistent/autosave_v4 boolean false | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean false | debconf-set-selections
apt-get update
apt-get install -y ipset dialog iptables-persistent
cp conf/blacklist /etc/cron.daily/blacklist
chmod a+x /etc/cron.daily/blacklist
source conf/tor.sh
echo iptables-persistent iptables-persistent/autosave_v4 boolean false | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean false | debconf-set-selections
apt-get update
apt-get install -y ipset dialog iptables-persistent
cp conf/iptables-persistent /etc/init.d/iptables-persistent
ipset create blacklist hash:net
iptables -I INPUT -m set --match-set blacklist src -j DROP
time /etc/cron.daily/blacklist
source conf/geoblock.sh 
/etc/init.d/iptables-persistent save
echo "Blacklist has been installed. It will run daily automatically."
