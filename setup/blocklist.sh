#!/bin/bash
# Add Blocklist.de malicious IP Addresses to Daily Crontab
# Also IPtables-persistent to save IP addresses upon reboot
# Added by Alon "ChiefGyk" Ganon
# alonganon.info
# alon@ganon.me
cp conf/blocklist/sync-fail2ban /etc/cron.daily/sync-fail2ban
chmod a+x /etc/cron.daily/sync-fail2ban
time /etc/cron.daily/sync-fail2ban
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
apt_install iptables-persistent