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
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
apt-get update
apt-get install -y ipset 
ipset create blacklist hash:net
iptables -I INPUT -m set --match-set blacklist src -j DROP
cp blacklist /etc/cron.daily/blacklist
chmod a+x /etc/cron.daily/blacklist
time /etc/cron.daily/blacklist
apt-get install -y iptables-persistent
echo "Blacklist has been installed. It will run daily automatically."
