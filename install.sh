# Add Blocklist.de malicious IP Addresses to Daily Crontab
# Also IPtables-persistent to save IP addresses upon reboot
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
apt-get update
apt-get install -y ipset 
mkdir /etc/ipset
ipset create blacklist hash:net
iptables -I INPUT -m set --match-set blacklist src -j DROP
cp blacklist /etc/cron.daily/blacklist
chmod a+x /etc/cron.daily/blacklist
time /etc/cron.daily/blacklist
iptables-save > /etc/iptables.up.rules
sed -e "\$apost up ipset restore < /etc/ipset/blacklist" /etc/network/interfaces
sed -e "\$apost up iptables-restore < /etc/iptables.up.rules" /etc/network/interfaces
echo "Blacklist has been installed. It will run daily automatically."
