# Add Blocklist.de malicious IP Addresses to Daily Crontab
# Also IPtables-persistent to save IP addresses upon reboot
# Added by Alon "ChiefGyk" Ganon
# alon@ganon.me

# Are we running as root?
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root. Please re-run like this:"
	echo
	echo "sudo $0"
	echo
	exit
fi
cp sync-fail2ban /etc/cron.daily/sync-fail2ban
mkdir /etc/iptables
cp blocklist.txt /etc/iptables/blocklist.txt
chmod a+x /etc/cron.daily/sync-fail2ban
time /etc/cron.daily/sync-fail2ban
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
apt-get update
apt-get install -y iptables-persistent
